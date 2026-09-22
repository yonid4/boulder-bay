"""Gym listing.

Busyness is resolved from `gym_hours` only for now: there are no snapshots or curves yet,
so `busy_pct`, `level` and `source` are always empty and `is_open` is the one real signal.
"""

from collections import defaultdict
from collections.abc import Iterable
from datetime import UTC, datetime
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.models import Gym, GymBrand, ResolvedBusyness
from app.db import models as db


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


def to_api_gym(row: db.Gym, *, at: datetime, hours: Iterable[db.GymHours]) -> Gym:
    """Build the list-view model for one gym row and its opening hours."""

    return Gym(
        slug=row.slug,
        name=row.name,
        brand=GymBrand(row.brand),
        city=row.city,
        latitude=row.latitude,
        longitude=row.longitude,
        # The logo route is not implemented yet; advertise nothing rather than a 501.
        logo_url=None,
        busyness=ResolvedBusyness(at=at, is_open=resolve_is_open(at, row.timezone, hours)),
    )


async def list_gyms(session: AsyncSession, *, at: datetime | None = None) -> list[Gym]:
    """All active gyms, ordered by name, with busyness resolved for `at` (default: now)."""

    if at is None:
        at = datetime.now(UTC)
    elif at.tzinfo is None:
        raise ValueError("`at` must carry a timezone offset")

    gyms_stmt = select(db.Gym).where(db.Gym.is_active).order_by(db.Gym.name)
    gyms = (await session.scalars(gyms_stmt)).all()
    if not gyms:
        return []

    hours_by_gym: defaultdict[int, list[db.GymHours]] = defaultdict(list)
    hours_stmt = select(db.GymHours).where(db.GymHours.gym_id.in_([gym.id for gym in gyms]))
    for row in (await session.scalars(hours_stmt)).all():
        hours_by_gym[row.gym_id].append(row)

    return [to_api_gym(gym, at=at, hours=hours_by_gym[gym.id]) for gym in gyms]
