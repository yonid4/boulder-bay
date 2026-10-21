"""One poll: read every gym through a provider and store what it saw.

`run_poll` is the unit a future scheduler job calls unchanged; today the one-shot
`python -m app.scrape` command drives it. Per gym it upserts the weekly curve into
`busyness_curves` and inserts one `busyness_snapshots` row for the tick.

Google renders a bar for every hour from 6 AM to 11 PM, with 0% for hours the gym is
closed. The schema forbids storing closed hours as 0 (see `BusynessCurve`), so only bars
that overlap the gym's `gym_hours` for that day are written.
"""

import logging
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime, time

from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import models as db
from app.scrape.parse import CrowdReading
from app.scrape.providers import CrowdProvider, ProviderUnavailable
from app.services.busyness import local_slot

logger = logging.getLogger(__name__)


@dataclass
class GymResult:
    slug: str
    attempts: int = 0
    reading: CrowdReading | None = None
    # Curve rows kept after dropping closed hours: written, or would be on a dry run.
    curve_rows: int = 0
    error: str | None = None

    @property
    def bars(self) -> int:
        return len(self.reading.bars) if self.reading else 0


@dataclass
class PollSummary:
    results: list[GymResult]

    @property
    def no_data(self) -> bool:
        """No gym produced a single bar: a DOM change, not a flaky load."""

        return all(result.bars == 0 for result in self.results)


def minutes(clock: time) -> int:
    return clock.hour * 60 + clock.minute


def open_during(hours: Iterable[db.GymHours], day_of_week: int, hour: int) -> bool:
    """Whether the gym is open at any point in local hour `hour` of `day_of_week`."""

    start, end = hour * 60, hour * 60 + 60
    return any(
        minutes(row.opens_at) < end and minutes(row.closes_at) > start
        for row in hours
        if row.day_of_week == day_of_week
    )


def curve_rows(
    reading: CrowdReading, hours: Sequence[db.GymHours], *, now: datetime, timezone: str
) -> dict[tuple[int, int], int]:
    """The (day_of_week, hour) -> percent rows to upsert for one reading.

    The current hour never has a bar (its element carries the live label), so it is
    filled from the label's "usually N%" instead.
    """

    rows = {slot: pct for slot, pct in reading.bars.items() if open_during(hours, *slot)}
    if reading.typical_pct is not None:
        slot = local_slot(now, timezone)
        if open_during(hours, *slot):
            rows[slot] = reading.typical_pct
    return rows


async def write_reading(
    session: AsyncSession,
    gym_id: int,
    reading: CrowdReading,
    rows: Mapping[tuple[int, int], int],
    *,
    now: datetime,
) -> None:
    """Upsert the curve rows and insert the tick's snapshot, in one transaction."""

    if rows:
        curve = pg_insert(db.BusynessCurve).values(
            [
                {
                    "gym_id": gym_id,
                    "day_of_week": day_of_week,
                    "hour_of_day": hour,
                    "busy_pct": pct,
                    "updated_at": now,
                }
                for (day_of_week, hour), pct in sorted(rows.items())
            ]
        )
        # Upsert, never delete-then-insert: a missing bar must not punch a hole.
        await session.execute(
            curve.on_conflict_do_update(
                index_elements=["gym_id", "day_of_week", "hour_of_day"],
                set_={"busy_pct": curve.excluded.busy_pct, "updated_at": curve.excluded.updated_at},
            )
        )
    snapshot = pg_insert(db.BusynessSnapshot).values(
        gym_id=gym_id,
        observed_at=now,
        live_pct=reading.live_pct,
        typical_pct=reading.typical_pct,
    )
    await session.execute(
        snapshot.on_conflict_do_nothing(constraint="busyness_snapshots_tick_unique")
    )
    await session.commit()


async def poll_gym(
    session: AsyncSession,
    provider: CrowdProvider,
    gym: db.Gym,
    hours: Sequence[db.GymHours],
    result: GymResult,
    *,
    now: datetime,
    dry_run: bool,
) -> bool:
    """One full attempt, fetch plus write. Logs and records a failure instead of raising."""

    result.attempts += 1
    try:
        reading = await provider.fetch(gym, now)
        result.reading = reading
        rows = curve_rows(reading, hours, now=now, timezone=gym.timezone)
        result.curve_rows = len(rows)
        if not dry_run:
            await write_reading(session, gym.id, reading, rows, now=now)
    except ProviderUnavailable:
        raise
    except Exception as error:
        if not dry_run:
            await session.rollback()
        result.error = f"{type(error).__name__}: {error}"
        logger.warning("%s attempt %d failed: %s", gym.slug, result.attempts, result.error)
        return False
    result.error = None
    return True


async def run_poll(
    session: AsyncSession,
    provider: CrowdProvider,
    gyms: Sequence[db.Gym],
    hours: Mapping[int, Sequence[db.GymHours]],
    *,
    now: datetime,
    dry_run: bool = False,
) -> PollSummary:
    """Poll every gym, then give each failed gym exactly one more full attempt.

    The retry waits for a second pass so a passing Google problem has time to clear.
    It is separate from the provider's own page-load retries inside a single fetch.
    `ProviderUnavailable` (e.g. an expired sign-in) stops the whole run.
    """

    results = {gym.id: GymResult(slug=gym.slug) for gym in gyms}
    failed = []
    for gym in gyms:
        if not await poll_gym(
            session, provider, gym, hours.get(gym.id, ()), results[gym.id], now=now, dry_run=dry_run
        ):
            failed.append(gym)
    for gym in failed:
        await poll_gym(
            session, provider, gym, hours.get(gym.id, ()), results[gym.id], now=now, dry_run=dry_run
        )
    return PollSummary([results[gym.id] for gym in gyms])
