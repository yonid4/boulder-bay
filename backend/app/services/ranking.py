"""Ranking score and the per-user weights behind it.

`score()` is a plain function -- no SQL, no clock -- so the formula is unit-testable:

    crowd = 0 if closed else (busy_pct if known else 50)
    score = 100
          - w_crowd  * crowd
          - w_travel * min(travel_minutes, travel_cap_minutes)
          + member_boost   if member
          - closed_penalty if closed

With the default weights this is the mockup's formula. Ordering and rounding belong to
the caller. Unknown busyness while open counts as 50 (the middle of Moderate): treating
it as 0 would make a scraper gap look like the best gym in the Bay.

`rank_gyms` is `GET /api/rankings`: one saved location's gyms within the straight-line
radius, scored for `at` and ordered best first.
"""

from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from sqlalchemy import ColumnElement, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.models import RankedGym, Rankings, SavedLocation
from app.db import models as db
from app.services.gyms import load_busyness_inputs, requested_instants, to_api_gym
from app.services.locations import get_default_location, get_location
from app.services.memberships import member_gym_ids
from app.services.travel import MapboxClient, travel_minutes

# A presentation offset, not a tunable (schema 2.8).
BASE_SCORE = 100.0
UNKNOWN_BUSY_PCT = 50.0


@dataclass(frozen=True)
class RankingWeights:
    w_crowd: float
    w_travel: float
    member_boost: float
    closed_penalty: float
    travel_cap_minutes: int

    @classmethod
    def from_prefs(cls, prefs: db.RankingPrefs) -> "RankingWeights":
        return cls(
            w_crowd=float(prefs.w_crowd),
            w_travel=float(prefs.w_travel),
            member_boost=float(prefs.member_boost),
            closed_penalty=float(prefs.closed_penalty),
            travel_cap_minutes=prefs.travel_cap_minutes,
        )


# Mirrors the `ranking_prefs` column defaults, i.e. the prototype formula.
DEFAULT_WEIGHTS = RankingWeights(
    w_crowd=0.6, w_travel=0.5, member_boost=15.0, closed_penalty=60.0, travel_cap_minutes=60
)


def score(
    *,
    busy_pct: float | None,
    is_open: bool,
    travel_minutes: float,
    is_member: bool,
    weights: RankingWeights = DEFAULT_WEIGHTS,
) -> float:
    """Score one gym; higher is a better pick. Returned unrounded."""

    if not is_open:
        crowd = 0.0
    elif busy_pct is None:
        crowd = UNKNOWN_BUSY_PCT
    else:
        crowd = busy_pct
    travel = min(travel_minutes, weights.travel_cap_minutes)

    result = BASE_SCORE - weights.w_crowd * crowd - weights.w_travel * travel
    if is_member:
        result += weights.member_boost
    if not is_open:
        result -= weights.closed_penalty
    return result


async def get_or_create_ranking_prefs(session: AsyncSession, user_id: UUID) -> db.RankingPrefs:
    """The user's prefs row, created with the column defaults on first use.

    `INSERT ... ON CONFLICT DO NOTHING` then `SELECT`, so concurrent first requests
    cannot collide. The caller owns the transaction.
    """

    await session.execute(
        pg_insert(db.RankingPrefs).values(user_id=user_id).on_conflict_do_nothing()
    )
    result = await session.scalars(
        select(db.RankingPrefs).where(db.RankingPrefs.user_id == user_id)
    )
    return result.one()


def within_radius(location: SavedLocation, radius_meters: int) -> ColumnElement[bool]:
    """`gyms.geog` within `radius_meters` of the location, as a `gyms_geog_idx` lookup.

    Always `ST_DWithin`, never `ST_Distance <= x`, which can't use the index (schema §4).
    The point is built like the generated `geog` columns, from the coordinates already
    loaded, so the prefilter and the travel times agree on where the location is.
    """

    point = func.extensions.geography(
        func.extensions.st_setsrid(
            func.extensions.st_makepoint(location.longitude, location.latitude), 4326
        )
    )
    return func.extensions.st_dwithin(db.Gym.geog, point, radius_meters)


async def rank_gyms(
    session: AsyncSession,
    *,
    user_id: UUID,
    location_id: UUID | None,
    mapbox: MapboxClient,
    radius_meters: int,
    limit: int,
    at: datetime | None = None,
    now: datetime | None = None,
    logo_url_for: Callable[[str], str] | None = None,
) -> Rankings:
    """`user_id`'s location `location_id` (default: their default location) with the active
    gyms within `radius_meters` of it, best first, at most `limit` of them.

    Busyness resolves for `at` (default: now) exactly as the gym list does. Order is score,
    high to low, then gym name A to Z; the sort uses the unrounded score, so a tie means truly
    equal. Travel time is already in the score, so there is no separate distance tie-break.

    Raises `ValueError` for a naive `at` before any query, `LocationNotFoundError` for a
    location the user doesn't own, and `NoLocationsError` when no id is given and the user
    has no locations. The prefs row and new travel times are committed together, once.
    """

    at, now = requested_instants(at, now)
    if location_id is None:
        location = await get_default_location(session, user_id=user_id)
    else:
        location = await get_location(session, user_id=user_id, location_id=location_id)

    weights = RankingWeights.from_prefs(await get_or_create_ranking_prefs(session, user_id))
    gyms_stmt = select(db.Gym).where(db.Gym.is_active, within_radius(location, radius_meters))
    gyms = (await session.scalars(gyms_stmt)).all()
    inputs = await load_busyness_inputs(session, gyms, at=at, now=now)
    member_ids = await member_gym_ids(session, user_id=user_id)
    estimates = await travel_minutes(session, location, gyms, mapbox=mapbox, now=now)
    await session.commit()

    scored = []
    for gym in gyms:
        busyness = inputs.resolve_for(gym)
        is_member = gym.id in member_ids
        minutes = estimates[gym.id].minutes
        gym_score = score(
            busy_pct=busyness.busy_pct,
            is_open=busyness.is_open,
            travel_minutes=minutes,
            is_member=is_member,
            weights=weights,
        )
        api_gym = to_api_gym(gym, busyness=busyness, is_member=is_member, logo_url_for=logo_url_for)
        scored.append((gym_score, minutes, api_gym))
    scored.sort(key=lambda item: (-item[0], item[2].name, item[2].slug))

    return Rankings(
        at=at,
        location=location,
        ranked_gyms=[
            RankedGym(rank=rank, score=gym_score, travel_minutes=minutes, gym=api_gym)
            for rank, (gym_score, minutes, api_gym) in enumerate(scored[:limit], start=1)
        ],
    )
