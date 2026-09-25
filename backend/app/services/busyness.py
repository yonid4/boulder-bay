"""Busyness resolution: when a gym is open, and how busy it is or is expected to be.

Everything here works in the gym's own timezone with Sunday as day zero, matching
`gym_hours.day_of_week` and `busyness_curves.day_of_week`.
"""

from collections.abc import Iterable
from datetime import datetime
from zoneinfo import ZoneInfo

from app.db import models as db


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
