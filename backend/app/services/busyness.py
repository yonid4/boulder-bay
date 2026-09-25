"""Busyness resolution: when a gym is open, and how busy it is or is expected to be.

Everything here works in the gym's own timezone with Sunday as day zero, matching
`gym_hours.day_of_week` and `busyness_curves.day_of_week`.

A requested instant resolves, in order, to: closed (per `gym_hours`); live (a fresh
snapshot, see `is_live`); forecast (the weekly curve's row for that local hour); or open
with no value, which means "no forecast" and is never shown as 0.
"""

from collections.abc import Iterable
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from app.api.models import BusynessLevel, BusynessSource, ResolvedBusyness
from app.db import models as db

# How old a snapshot may be, by the wall clock, and still count as live.
LIVE_MAX_AGE = timedelta(minutes=45)


def local_slot(at: datetime, timezone: str) -> tuple[int, int]:
    """The (day_of_week, hour_of_day) that the instant `at` falls in, locally."""

    local = at.astimezone(ZoneInfo(timezone))
    return local.isoweekday() % 7, local.hour


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


def resolve_busyness(
    at: datetime,
    *,
    now: datetime,
    timezone: str,
    hours: Iterable[db.GymHours],
    curve_pct: int | None,
    snapshot: db.BusynessSnapshot | None,
) -> ResolvedBusyness:
    """Resolve one gym for `at`. `curve_pct` is the curve row for `at`'s local hour."""

    if not resolve_is_open(at, timezone, hours):
        return ResolvedBusyness(at=at, is_open=False)
    if (
        snapshot is not None
        and snapshot.live_pct is not None
        and is_live(at, now, timezone, snapshot.observed_at)
    ):
        return ResolvedBusyness(
            at=at,
            is_open=True,
            busy_pct=snapshot.live_pct,
            level=level_for(snapshot.live_pct),
            source=BusynessSource.LIVE,
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
