"""One poll: read every gym through a provider and store what it saw.

`load_and_poll` is the whole "load, filter open, poll" run; the one-shot
`python -m app.scrape` command and the scheduler's tick both call it. Per gym it upserts
the weekly curve into `busyness_curves` and inserts one `busyness_snapshots` row for the tick.

Google renders a bar for every hour from 6 AM to 11 PM, with 0% for hours the gym is
closed. The schema forbids storing closed hours as 0 (see `BusynessCurve`), so only bars
that overlap the gym's `gym_hours` for that day are written.
"""

import logging
from collections.abc import Callable, Mapping, Sequence
from contextlib import AbstractAsyncContextManager
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import models as db
from app.scrape.parse import CrowdReading
from app.scrape.providers import CrowdProvider, ProviderUnavailable
from app.services.busyness import local_slot, open_during, resolve_is_open

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

        return bool(self.results) and all(result.bars == 0 for result in self.results)


async def load_gyms(
    session: AsyncSession, slugs: Sequence[str]
) -> tuple[list[db.Gym], dict[int, list[db.GymHours]]]:
    """Active gyms by name, optionally limited to `slugs`, and their opening hours."""

    gyms_stmt = select(db.Gym).where(db.Gym.is_active).order_by(db.Gym.name)
    if slugs:
        gyms_stmt = gyms_stmt.where(db.Gym.slug.in_(slugs))
    gyms = list((await session.scalars(gyms_stmt)).all())
    if missing := sorted(set(slugs) - {gym.slug for gym in gyms}):
        raise LookupError(f"unknown or inactive gym slug(s): {', '.join(missing)}")

    hours: dict[int, list[db.GymHours]] = {gym.id: [] for gym in gyms}
    hours_stmt = select(db.GymHours).where(db.GymHours.gym_id.in_(hours))
    for row in (await session.scalars(hours_stmt)).all():
        hours[row.gym_id].append(row)
    return gyms, hours


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


async def load_and_poll(
    session: AsyncSession,
    open_provider: Callable[[], AbstractAsyncContextManager[CrowdProvider]],
    *,
    now: datetime,
    slugs: Sequence[str] = (),
    open_only: bool = False,
    dry_run: bool = False,
) -> PollSummary:
    """Load the gyms, optionally keep those open at `now`, and poll them with one provider.

    `open_provider` is called only when there is something to poll, so a run in which every
    gym is closed never launches a browser; its summary is empty and not `no_data`. The
    provider is entered once and closed when the poll ends. Raises `LookupError` for an
    unknown slug and lets `ProviderUnavailable` through, like `load_gyms` and `run_poll`.
    """

    gyms, hours = await load_gyms(session, slugs)
    # End the read transaction; it would otherwise idle through the whole poll.
    await session.commit()
    if open_only:
        gyms = [gym for gym in gyms if resolve_is_open(now, gym.timezone, hours[gym.id])]
    if not gyms:
        return PollSummary([])
    async with open_provider() as provider:
        return await run_poll(session, provider, gyms, hours, now=now, dry_run=dry_run)
