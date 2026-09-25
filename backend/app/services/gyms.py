"""Gym listing.

Busyness is resolved from `gym_hours` only for now: there are no snapshots or curves yet,
so `busy_pct`, `level` and `source` are always empty and `is_open` is the one real signal.
"""

from collections import defaultdict
from collections.abc import Iterable
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.models import Gym, GymBrand, ResolvedBusyness
from app.db import models as db
from app.services.busyness import resolve_is_open


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
