"""Travel minutes from a saved location to gyms, cached in `travel_times`.

Stage 2 of rankings (`boulder_bay_v1_design.md` §7). The caller has already narrowed the gyms
with the straight-line prefilter; `travel_minutes` then:

1. reads the cached `travel_times` rows for the location and those gyms;
2. keeps the fresh ones: `mapbox` rows under 30 days old, `haversine_fallback` rows under an
   hour old;
3. asks the Mapbox Matrix API (`driving`, not `driving-traffic`: the cache lives for weeks) for
   only the missing or stale pairs, in one request per 24 destinations, and upserts them;
4. when the token is empty, or Mapbox errors or times out (5 s), uses `6 + miles x 2.3` from
   the haversine distance instead and upserts that as `haversine_fallback`, so it is retried
   within the hour. A pair Mapbox can't route gets the fallback too.

Rankings never fails because of Mapbox. Moving a location already deletes its rows (see
`services/locations.py`), so freshness is the only check here. Like
`get_or_create_ranking_prefs`, this does not commit: the caller owns the transaction.
"""

import logging
import math
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal
from functools import lru_cache
from typing import Any, Literal, NamedTuple

import httpx
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.models import SavedLocation
from app.config import get_settings
from app.db import models as db

logger = logging.getLogger(__name__)

TravelProvider = Literal["mapbox", "haversine_fallback"]

MAPBOX_MAX_AGE = timedelta(days=30)
FALLBACK_MAX_AGE = timedelta(hours=1)
MAPBOX_TIMEOUT_SECONDS = 5.0
MAPBOX_MATRIX_URL = "https://api.mapbox.com/directions-matrix/v1/mapbox/driving"
# The Matrix API takes at most 25 coordinates per request: the origin plus 24 gyms.
MAPBOX_MAX_DESTINATIONS = 24

# The fallback formula from the plan: a fixed overhead plus minutes per straight-line mile.
FALLBACK_BASE_MINUTES = 6.0
FALLBACK_MINUTES_PER_MILE = 2.3
METERS_PER_MILE = 1609.344
EARTH_RADIUS_METERS = 6_371_008.8  # mean radius

_MINUTES_QUANTUM = Decimal("0.01")  # travel_times.minutes is numeric(6,2)
_MAX_MINUTES = Decimal("9999.99")


class TravelEstimate(NamedTuple):
    """Minutes from the location to one gym, and where the number came from."""

    minutes: float
    provider: TravelProvider


@dataclass(frozen=True)
class Route:
    """One Mapbox origin-to-destination result."""

    seconds: float
    meters: float | None


class MapboxError(Exception):
    """The Matrix API failed, timed out, or answered with something unusable."""


@dataclass(frozen=True)
class MapboxClient:
    """The Mapbox Matrix API, `driving` profile.

    An empty token means "not configured": `travel_minutes` then never calls it. A client is
    opened per request because the cache keeps calls to about one per place per 30 days.
    `transport` exists for tests (`httpx.MockTransport`).
    """

    token: str
    timeout_seconds: float = MAPBOX_TIMEOUT_SECONDS
    transport: httpx.AsyncBaseTransport | None = None

    @property
    def configured(self) -> bool:
        return bool(self.token)

    async def routes(
        self, origin: tuple[float, float], destinations: Sequence[tuple[float, float]]
    ) -> list[Route | None]:
        """Driving routes from `origin` to each destination, in order; None where unroutable.

        Points are `(latitude, longitude)`. Raises `MapboxError` on any failure. The error
        never carries the request URL, which holds the token.
        """

        if not destinations:
            return []
        routes: list[Route | None] = []
        async with httpx.AsyncClient(
            timeout=self.timeout_seconds, transport=self.transport
        ) as client:
            for start in range(0, len(destinations), MAPBOX_MAX_DESTINATIONS):
                chunk = destinations[start : start + MAPBOX_MAX_DESTINATIONS]
                routes.extend(await self._matrix(client, origin, chunk))
        return routes

    async def _matrix(
        self,
        client: httpx.AsyncClient,
        origin: tuple[float, float],
        destinations: Sequence[tuple[float, float]],
    ) -> list[Route | None]:
        # Mapbox wants longitude,latitude.
        coordinates = ";".join(f"{lon:.6f},{lat:.6f}" for lat, lon in [origin, *destinations])
        params = {
            "sources": "0",
            "destinations": ";".join(str(i) for i in range(1, len(destinations) + 1)),
            "annotations": "duration,distance",
            "access_token": self.token,
        }
        try:
            response = await client.get(f"{MAPBOX_MATRIX_URL}/{coordinates}", params=params)
        except httpx.HTTPError as error:
            raise MapboxError(f"Matrix request failed: {type(error).__name__}") from None
        if response.status_code != httpx.codes.OK:
            raise MapboxError(f"Matrix request returned HTTP {response.status_code}")
        try:
            return _parse_matrix(response.json(), len(destinations))
        except (AttributeError, ValueError, KeyError, TypeError, IndexError) as error:
            raise MapboxError(f"Matrix response unusable: {error}") from None


def _parse_matrix(body: Any, expected: int) -> list[Route | None]:
    if body.get("code") != "Ok":
        raise ValueError(f"code {body.get('code')!r}")
    durations = body["durations"][0]
    distances = body.get("distances", [[None] * expected])[0]
    if len(durations) != expected or len(distances) != expected:
        raise ValueError(f"expected {expected} destinations, got {len(durations)}")
    routes: list[Route | None] = []
    for seconds, meters in zip(durations, distances, strict=True):
        if seconds is None:
            routes.append(None)
        else:
            routes.append(
                Route(seconds=float(seconds), meters=None if meters is None else float(meters))
            )
    return routes


@lru_cache
def get_mapbox_client() -> MapboxClient:
    """The client for the configured `MAPBOX_TOKEN` (possibly empty, i.e. fallback only)."""

    return MapboxClient(token=get_settings().mapbox_token)


def haversine_meters(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Great-circle distance between two `(latitude, longitude)` points."""

    lat1, lon1 = map(math.radians, a)
    lat2, lon2 = map(math.radians, b)
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 2 * EARTH_RADIUS_METERS * math.asin(math.sqrt(h))


def fallback_minutes(meters: float) -> float:
    """`6 + miles x 2.3`: the plan's stand-in for a driving time."""

    return FALLBACK_BASE_MINUTES + meters / METERS_PER_MILE * FALLBACK_MINUTES_PER_MILE


def is_fresh(row: db.TravelTime, now: datetime) -> bool:
    """Mapbox rows last 30 days; fallback rows an hour, so Mapbox gets retried soon."""

    max_age = MAPBOX_MAX_AGE if row.provider == "mapbox" else FALLBACK_MAX_AGE
    return now - row.computed_at < max_age


def _minutes(value: float) -> Decimal:
    """Rounded and clamped to fit numeric(6,2); the radius prefilter keeps real values far below."""

    return min(Decimal(str(value)).quantize(_MINUTES_QUANTUM, rounding=ROUND_HALF_UP), _MAX_MINUTES)


async def travel_minutes(
    session: AsyncSession,
    location: SavedLocation,
    gyms: Sequence[db.Gym],
    *,
    mapbox: MapboxClient,
    now: datetime | None = None,
) -> dict[int, TravelEstimate]:
    """Minutes from `location` to each of `gyms`, keyed by gym id; every gym gets one.

    One read, at most one Mapbox request (per 24 gyms) and one upsert, and nothing at all for
    no gyms. Never raises because of Mapbox. Does not commit.
    """

    if not gyms:
        return {}
    if now is None:
        now = datetime.now(UTC)
    gym_ids = [gym.id for gym in gyms]

    cached = await session.scalars(
        select(db.TravelTime).where(
            db.TravelTime.location_id == location.id, db.TravelTime.gym_id.in_(gym_ids)
        )
    )
    result: dict[int, TravelEstimate] = {}
    for row in cached:
        if is_fresh(row, now):
            provider: TravelProvider = (
                "mapbox" if row.provider == "mapbox" else "haversine_fallback"
            )
            result[row.gym_id] = TravelEstimate(float(row.minutes), provider)

    missing = [gym for gym in gyms if gym.id not in result]
    if not missing:
        return result

    origin = (location.latitude, location.longitude)
    routes: list[Route | None] = [None] * len(missing)
    if mapbox.configured:
        try:
            routes = await mapbox.routes(origin, [(g.latitude, g.longitude) for g in missing])
        except MapboxError as error:
            logger.warning("Mapbox unavailable, using the haversine fallback: %s", error)

    upserts: list[dict[str, Any]] = []
    for gym, route in zip(missing, routes, strict=True):
        if route is None:
            minutes = _minutes(
                fallback_minutes(haversine_meters(origin, (gym.latitude, gym.longitude)))
            )
            meters: int | None = None
            provider = "haversine_fallback"
        else:
            minutes = _minutes(route.seconds / 60)
            meters = None if route.meters is None else round(route.meters)
            provider = "mapbox"
        result[gym.id] = TravelEstimate(float(minutes), provider)
        upserts.append(
            {
                "location_id": location.id,
                "gym_id": gym.id,
                "minutes": minutes,
                "meters": meters,
                "provider": provider,
                "computed_at": now,
            }
        )

    stmt = pg_insert(db.TravelTime).values(upserts)
    await session.execute(
        stmt.on_conflict_do_update(
            index_elements=[db.TravelTime.location_id, db.TravelTime.gym_id],
            set_={
                "minutes": stmt.excluded.minutes,
                "meters": stmt.excluded.meters,
                "provider": stmt.excluded.provider,
                "computed_at": stmt.excluded.computed_at,
            },
        )
    )
    return result
