"""Gym listing and detail.

Busyness is resolved per gym by `app.services.busyness.resolve_busyness`: closed per
`gym_hours`, else a live snapshot, else the mean of a finished hour's snapshots, else the
weekly curve, else open with no value. The list takes five queries in all, however many
gyms: gyms, the three in `load_busyness_inputs`, then the caller's memberships. The detail
takes seven: the gym, those three, the local day's curve rows and snapshots for the
forecast, then whether the caller is a member.
"""

from collections import defaultdict
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import and_, or_, select, tuple_
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.models import (
    BusynessForecast,
    Gym,
    GymBrand,
    GymDetail,
    GymHours,
    GymRates,
    ResolvedBusyness,
)
from app.db import models as db
from app.services.busyness import (
    LIVE_MAX_AGE,
    best_time,
    forecast_points,
    local_day,
    local_hour,
    local_slot,
    resolve_busyness,
)


@dataclass(frozen=True)
class GymLogoImage:
    """The columns the logo route serves, without the audit timestamps."""

    image: bytes
    content_type: str
    sha256: str


async def get_gym_logo(session: AsyncSession, slug: str) -> GymLogoImage | None:
    """The logo assigned to the active gym `slug`; None for an unknown slug or no logo."""

    stmt = (
        select(db.GymLogo.image, db.GymLogo.content_type, db.GymLogo.sha256)
        .join(db.Gym, db.Gym.logo_id == db.GymLogo.id)
        .where(db.Gym.slug == slug, db.Gym.is_active)
    )
    row = (await session.execute(stmt)).one_or_none()
    if row is None:
        return None
    image, content_type, sha256 = row
    return GymLogoImage(image=image, content_type=content_type, sha256=sha256)


@dataclass(frozen=True)
class BusynessInputs:
    """Everything needed to resolve busyness at `at` for a set of gyms, keyed by gym id."""

    at: datetime
    now: datetime
    hours: dict[int, list[db.GymHours]]
    curve_pct: dict[int, int]
    snapshots: dict[int, list[db.BusynessSnapshot]]

    def resolve_for(self, gym: db.Gym) -> ResolvedBusyness:
        """Resolve one of the loaded gyms at `at`; a gym with no rows resolves closed."""

        return resolve_busyness(
            self.at,
            now=self.now,
            timezone=gym.timezone,
            hours=self.hours.get(gym.id, []),
            curve_pct=self.curve_pct.get(gym.id),
            snapshots=self.snapshots.get(gym.id, []),
        )


async def load_busyness_inputs(
    session: AsyncSession, gyms: Sequence[db.Gym], *, at: datetime, now: datetime
) -> BusynessInputs:
    """Load hours, curve rows and snapshots to resolve `gyms` at `at`.

    Three queries however many gyms, and none when there are none: the gyms' hours, the
    curve rows for each gym's local hour at `at`, and each gym's snapshots inside either the
    live window before `now` or its local hour at `at`. `at` must carry a timezone offset.
    """

    if not gyms:
        return BusynessInputs(at=at, now=now, hours={}, curve_pct={}, snapshots={})
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

    return BusynessInputs(
        at=at,
        now=now,
        hours=dict(hours_by_gym),
        curve_pct=curve_pct,
        snapshots=dict(snapshots_by_gym),
    )


def to_api_gym(
    row: db.Gym,
    *,
    busyness: ResolvedBusyness,
    is_member: bool,
    logo_url_for: Callable[[str], str] | None = None,
) -> Gym:
    """Build the list-view model for one gym row, its resolved busyness and membership.

    `logo_url_for` maps a slug to the absolute logo URL; the URL is set only for gyms
    that have a logo.
    """

    return Gym(
        slug=row.slug,
        name=row.name,
        brand=GymBrand(row.brand),
        city=row.city,
        latitude=row.latitude,
        longitude=row.longitude,
        logo_url=logo_url_for(row.slug) if logo_url_for and row.logo_id is not None else None,
        is_member=is_member,
        busyness=busyness,
    )


async def list_gyms(
    session: AsyncSession,
    *,
    user_id: UUID,
    at: datetime | None = None,
    now: datetime | None = None,
    logo_url_for: Callable[[str], str] | None = None,
) -> list[Gym]:
    """All active gyms, ordered by name, with busyness resolved for `at` (default: now).

    `is_member` is set from `user_id`'s memberships, loaded in one query for all gyms.

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
    inputs = await load_busyness_inputs(session, gyms, at=at, now=now)
    member_ids = set(
        (
            await session.scalars(
                select(db.GymMembership.gym_id).where(db.GymMembership.user_id == user_id)
            )
        ).all()
    )
    return [
        to_api_gym(
            gym,
            busyness=inputs.resolve_for(gym),
            is_member=gym.id in member_ids,
            logo_url_for=logo_url_for,
        )
        for gym in gyms
    ]


def requested_instants(at: datetime | None, now: datetime | None) -> tuple[datetime, datetime]:
    """`(at, now)` with both defaulted to the wall clock; a naive `at` is a ValueError."""

    if now is None:
        now = datetime.now(UTC)
    if at is None:
        return now, now
    if at.tzinfo is None:
        raise ValueError("`at` must carry a timezone offset")
    return at, now


async def get_gym_detail(
    session: AsyncSession,
    slug: str,
    *,
    user_id: UUID,
    at: datetime | None = None,
    now: datetime | None = None,
    logo_url_for: Callable[[str], str] | None = None,
) -> GymDetail | None:
    """The active gym `slug` with busyness resolved for `at` (default: now) and the
    forecast for the gym's local day containing `at`; None for an unknown or inactive slug.

    Seven queries: the gym, the three in `load_busyness_inputs` (so `gym` resolves exactly
    as the list does), the gym's curve rows for that local weekday and its snapshots
    inside that local day or the live window before `now`, then whether `user_id` is a
    member. `now` is a parameter only so tests can pin it.
    """

    at, now = requested_instants(at, now)

    gym_stmt = select(db.Gym).where(db.Gym.slug == slug, db.Gym.is_active)
    gym = (await session.scalars(gym_stmt)).first()
    if gym is None:
        return None
    inputs = await load_busyness_inputs(session, [gym], at=at, now=now)
    hours = inputs.hours.get(gym.id, [])

    day, day_start, day_end = local_day(at, gym.timezone)
    day_of_week, _ = local_slot(at, gym.timezone)
    curve_stmt = select(db.BusynessCurve).where(
        db.BusynessCurve.gym_id == gym.id, db.BusynessCurve.day_of_week == day_of_week
    )
    curve = {row.hour_of_day: row.busy_pct for row in (await session.scalars(curve_stmt)).all()}
    snapshot_stmt = select(db.BusynessSnapshot).where(
        db.BusynessSnapshot.gym_id == gym.id,
        db.BusynessSnapshot.observed_at <= now,
        or_(
            db.BusynessSnapshot.observed_at > now - LIVE_MAX_AGE,
            and_(
                db.BusynessSnapshot.observed_at >= day_start,
                db.BusynessSnapshot.observed_at < day_end,
            ),
        ),
    )
    snapshots = (await session.scalars(snapshot_stmt)).all()
    member_stmt = select(db.GymMembership.gym_id).where(
        db.GymMembership.user_id == user_id, db.GymMembership.gym_id == gym.id
    )
    is_member = (await session.scalars(member_stmt)).first() is not None

    return GymDetail(
        gym=to_api_gym(
            gym,
            busyness=inputs.resolve_for(gym),
            is_member=is_member,
            logo_url_for=logo_url_for,
        ),
        address=gym.address,
        timezone=gym.timezone,
        website_url=gym.website_url,
        waiver_url=gym.waiver_url,
        hours=[
            GymHours(day_of_week=row.day_of_week, opens_at=row.opens_at, closes_at=row.closes_at)
            for row in sorted(hours, key=lambda row: (row.day_of_week, row.opens_at))
        ],
        rates=GymRates(
            day_pass_cents=gym.day_pass_cents,
            day_pass_peak_cents=gym.day_pass_peak_cents,
            peak_starts_at=gym.peak_starts_at,
            monthly_cents=gym.monthly_cents,
        ),
        forecast=BusynessForecast(
            date=day,
            timezone=gym.timezone,
            points=forecast_points(
                at,
                now=now,
                timezone=gym.timezone,
                hours=hours,
                curve=curve,
                snapshots=snapshots,
            ),
            best_time=best_time(at, timezone=gym.timezone, hours=hours, curve=curve),
        ),
    )
