"""Gym listing.

Busyness is resolved per gym by `app.services.busyness.resolve_busyness`: closed per
`gym_hours`, else a live snapshot, else the mean of a finished hour's snapshots, else the
weekly curve, else open with no value. Four queries in all, however many gyms: gyms,
hours, the curve rows for each gym's local hour at `at`, and each gym's snapshots inside
either the live window or its local hour at `at`.
"""

from collections import defaultdict
from datetime import UTC, datetime

from sqlalchemy import and_, or_, select, tuple_
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.models import Gym, GymBrand, ResolvedBusyness
from app.db import models as db
from app.services.busyness import LIVE_MAX_AGE, local_hour, local_slot, resolve_busyness


def to_api_gym(row: db.Gym, *, busyness: ResolvedBusyness) -> Gym:
    """Build the list-view model for one gym row and its resolved busyness."""

    return Gym(
        slug=row.slug,
        name=row.name,
        brand=GymBrand(row.brand),
        city=row.city,
        latitude=row.latitude,
        longitude=row.longitude,
        # The logo route is not implemented yet; advertise nothing rather than a 501.
        logo_url=None,
        busyness=busyness,
    )


async def list_gyms(
    session: AsyncSession, *, at: datetime | None = None, now: datetime | None = None
) -> list[Gym]:
    """All active gyms, ordered by name, with busyness resolved for `at` (default: now).

    `now` is the wall clock that decides whether a snapshot is still live; it is a
    parameter only so tests can pin it.
    """

    if now is None:
        now = datetime.now(UTC)
    if at is None:
        at = now
    elif at.tzinfo is None:
        raise ValueError("`at` must carry a timezone offset")

    gyms_stmt = select(db.Gym).where(db.Gym.is_active).order_by(db.Gym.name)
    gyms = (await session.scalars(gyms_stmt)).all()
    if not gyms:
        return []
    gym_ids = [gym.id for gym in gyms]

    hours_by_gym: defaultdict[int, list[db.GymHours]] = defaultdict(list)
    hours_stmt = select(db.GymHours).where(db.GymHours.gym_id.in_(gym_ids))
    for row in (await session.scalars(hours_stmt)).all():
        hours_by_gym[row.gym_id].append(row)

    # Each gym's own local (day, hour) at `at`: timezones may differ between gyms.
    slots = [(gym.id, *local_slot(at, gym.timezone)) for gym in gyms]
    curve_stmt = select(db.BusynessCurve).where(
        tuple_(
            db.BusynessCurve.gym_id, db.BusynessCurve.day_of_week, db.BusynessCurve.hour_of_day
        ).in_(slots)
    )
    curve_pct = {row.gym_id: row.busy_pct for row in (await session.scalars(curve_stmt)).all()}

    # Each gym's snapshots inside the live window (the latest is the live candidate) or
    # its local hour at `at` (averaged once that hour is over): at most a few rows per gym,
    # served by the (gym_id, observed_at) unique index. Gyms sharing a timezone share an
    # hour, so the hour conditions collapse to one per distinct hour.
    gyms_by_hour: defaultdict[tuple[datetime, datetime], list[int]] = defaultdict(list)
    for gym in gyms:
        gyms_by_hour[local_hour(at, gym.timezone)].append(gym.id)
    snapshot_stmt = select(db.BusynessSnapshot).where(
        db.BusynessSnapshot.gym_id.in_(gym_ids),
        db.BusynessSnapshot.observed_at <= now,
        or_(
            db.BusynessSnapshot.observed_at > now - LIVE_MAX_AGE,
            *(
                and_(
                    db.BusynessSnapshot.gym_id.in_(ids),
                    db.BusynessSnapshot.observed_at >= start,
                    db.BusynessSnapshot.observed_at < end,
                )
                for (start, end), ids in gyms_by_hour.items()
            ),
        ),
    )
    snapshots_by_gym: defaultdict[int, list[db.BusynessSnapshot]] = defaultdict(list)
    for snapshot in (await session.scalars(snapshot_stmt)).all():
        snapshots_by_gym[snapshot.gym_id].append(snapshot)

    return [
        to_api_gym(
            gym,
            busyness=resolve_busyness(
                at,
                now=now,
                timezone=gym.timezone,
                hours=hours_by_gym[gym.id],
                curve_pct=curve_pct.get(gym.id),
                snapshots=snapshots_by_gym[gym.id],
            ),
        )
        for gym in gyms
    ]
