"""Busyness resolution: when a gym is open, and how busy it is or is expected to be.

Everything here works in the gym's own timezone with Sunday as day zero, matching
`gym_hours.day_of_week` and `busyness_curves.day_of_week`.

A requested instant resolves, in order, to: closed (per `gym_hours`); live (a fresh
snapshot, see `is_live`); observed (the mean of the snapshots taken during that local
hour, once it is over, see `observed_pct`); forecast (the weekly curve's row for that
local hour); or open with no value, which means "no forecast" and is never shown as 0.
"""

from collections.abc import Iterable, Mapping, Sequence
from datetime import UTC, datetime, time, timedelta
from zoneinfo import ZoneInfo

from app.api.models import BusynessLevel, BusynessSource, ForecastPoint, ResolvedBusyness
from app.db import models as db

# How old a snapshot may be, by the wall clock, and still count as live.
LIVE_MAX_AGE = timedelta(minutes=45)


def local_slot(at: datetime, timezone: str) -> tuple[int, int]:
    """The (day_of_week, hour_of_day) that the instant `at` falls in, locally."""

    local = at.astimezone(ZoneInfo(timezone))
    return local.isoweekday() % 7, local.hour


def local_hour(at: datetime, timezone: str) -> tuple[datetime, datetime]:
    """The UTC bounds `[start, end)` of the local hour that the instant `at` falls in."""

    local = at.astimezone(ZoneInfo(timezone))
    start = local.replace(minute=0, second=0, microsecond=0).astimezone(UTC)
    return start, start + timedelta(hours=1)


def resolve_is_open(at: datetime, timezone: str, hours: Iterable[db.GymHours]) -> bool:
    """Whether a gym with these opening hours is open at the instant `at`.

    `hours` must already be this gym's rows. The day and clock time are taken in the gym's
    own timezone, with Sunday as day zero to match `gym_hours.day_of_week`. Closing is
    exclusive, and a day with no row is closed. Past-midnight closing cannot occur
    (`gym_hours_ordered`), so a single day's row is enough.
    """

    local = at.astimezone(ZoneInfo(timezone))
    day_of_week = local.isoweekday() % 7
    clock = local.time()
    return any(
        row.opens_at <= clock < row.closes_at for row in hours if row.day_of_week == day_of_week
    )


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


def level_for(pct: int) -> BusynessLevel:
    """Quiet below 40%, moderate from 40-69%, and packed from 70%."""

    if pct < 40:
        return BusynessLevel.QUIET
    if pct < 70:
        return BusynessLevel.MODERATE
    return BusynessLevel.PACKED


def is_live(at: datetime, now: datetime, timezone: str, observed_at: datetime) -> bool:
    """Whether a snapshot observed at `observed_at` speaks for the requested `at`.

    Live means now, by the wall clock: `at` must fall in the gym's current local hour
    (the app asks for the top of the hour, so 14:00 still counts at 14:50), and the
    snapshot must be under `LIVE_MAX_AGE` old at `now`. Scrubbing to any other hour
    always shows the forecast.
    """

    zone = ZoneInfo(timezone)
    at_hour = at.astimezone(zone).replace(minute=0, second=0, microsecond=0)
    now_hour = now.astimezone(zone).replace(minute=0, second=0, microsecond=0)
    return at_hour == now_hour and now - LIVE_MAX_AGE < observed_at <= now


def observed_pct(
    at: datetime, now: datetime, timezone: str, snapshots: Iterable[db.BusynessSnapshot]
) -> int | None:
    """The mean live reading over `at`'s local hour, once that hour is over at `now`.

    Any finished hour, on any day, counts. Snapshots without a live reading are skipped,
    and an hour with none left has no observed value. The hour in progress never has
    one: it is either live or forecast.
    """

    start, end = local_hour(at, timezone)
    if end > now:
        return None
    readings = [
        row.live_pct
        for row in snapshots
        if row.live_pct is not None and start <= row.observed_at < end
    ]
    if not readings:
        return None
    return round(sum(readings) / len(readings))


def resolve_busyness(
    at: datetime,
    *,
    now: datetime,
    timezone: str,
    hours: Iterable[db.GymHours],
    curve_pct: int | None,
    snapshots: Sequence[db.BusynessSnapshot],
) -> ResolvedBusyness:
    """Resolve one gym for `at`.

    `curve_pct` is the curve row for `at`'s local hour. `snapshots` must cover both the
    live window before `now` and `at`'s local hour; the latest of them is the live
    candidate.
    """

    if not resolve_is_open(at, timezone, hours):
        return ResolvedBusyness(at=at, is_open=False)
    latest = max(snapshots, key=lambda row: row.observed_at, default=None)
    if (
        latest is not None
        and latest.live_pct is not None
        and is_live(at, now, timezone, latest.observed_at)
    ):
        return ResolvedBusyness(
            at=at,
            is_open=True,
            busy_pct=latest.live_pct,
            level=level_for(latest.live_pct),
            source=BusynessSource.LIVE,
        )
    observed = observed_pct(at, now, timezone, snapshots)
    if observed is not None:
        return ResolvedBusyness(
            at=at,
            is_open=True,
            busy_pct=observed,
            level=level_for(observed),
            source=BusynessSource.OBSERVED,
        )
    if curve_pct is not None:
        return ResolvedBusyness(
            at=at,
            is_open=True,
            busy_pct=curve_pct,
            level=level_for(curve_pct),
            source=BusynessSource.FORECAST,
        )
    return ResolvedBusyness(at=at, is_open=True)


def best_time(
    at: datetime,
    *,
    timezone: str,
    hours: Iterable[db.GymHours],
    curve: Mapping[int, int],
) -> ForecastPoint | None:
    """The quietest open hour still to come on `at`'s local day, or None.

    `curve` maps local hour to the curve's `busy_pct` for that day of the week. Only
    hours that start after `at`'s local hour and that the gym is open for at all
    (`open_during`) and that have a curve row can be picked; the lowest percentage wins
    and ties go to the earliest hour. The curve is used rather than live or observed
    values because this predicts the future. None means no hour qualifies.
    """

    hours = list(hours)
    day_of_week, current_hour = local_slot(at, timezone)
    candidates = [
        (curve[hour], hour)
        for hour in range(current_hour + 1, 24)
        if hour in curve and open_during(hours, day_of_week, hour)
    ]
    if not candidates:
        return None
    pct, hour = min(candidates)
    local = at.astimezone(ZoneInfo(timezone))
    start, end = local_hour(local.replace(hour=hour), timezone)
    return ForecastPoint(
        starts_at=start,
        ends_at=end,
        busy_pct=pct,
        level=level_for(pct),
        source=BusynessSource.FORECAST,
    )
