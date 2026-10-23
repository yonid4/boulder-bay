import json
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any
from uuid import UUID

import httpx
import pytest
from sqlalchemy.dialects import postgresql

from app.api.models import SavedLocation
from app.db import models as db
from app.services.travel import (
    FALLBACK_MAX_AGE,
    MAPBOX_MAX_AGE,
    MapboxClient,
    MapboxError,
    Route,
    TravelEstimate,
    fallback_minutes,
    get_mapbox_client,
    haversine_meters,
    is_fresh,
    travel_minutes,
)

NOW = datetime(2026, 10, 23, 18, 0, tzinfo=UTC)
LOCATION_ID = UUID("d16878be-c4bc-462f-8929-c464b6a5efad")
LOCATION = SavedLocation(
    id=LOCATION_ID,
    label="Home",
    latitude=37.4852,
    longitude=-122.2364,
    is_default=True,
    kind="home",
)
TOKEN = "pk.test-token"


def gym(gym_id: int, latitude: float, longitude: float) -> db.Gym:
    return db.Gym(id=gym_id, slug=f"gym-{gym_id}", latitude=latitude, longitude=longitude)


GYMS = [
    gym(1, 37.4419, -122.1430),  # Palo Alto-ish
    gym(2, 37.7749, -122.4194),  # San Francisco
    gym(3, 37.8044, -122.2712),  # Oakland
]


def cached(gym_id: int, minutes: str, provider: str, age: timedelta) -> db.TravelTime:
    return db.TravelTime(
        location_id=LOCATION_ID,
        gym_id=gym_id,
        minutes=Decimal(minutes),
        meters=None,
        provider=provider,
        computed_at=NOW - age,
    )


def sql(statement: Any) -> str:
    return str(statement.compile(dialect=postgresql.dialect())).lower()


def upserted(statement: Any) -> list[dict[str, Any]]:
    """The rows an `INSERT ... VALUES (...), (...)` would write, one dict per row."""

    params = statement.compile(dialect=postgresql.dialect()).params
    count = len({key.rsplit("_m", 1)[1] for key in params if "_m" in key})
    columns = ("location_id", "gym_id", "minutes", "meters", "provider", "computed_at")
    return [{column: params[f"{column}_m{i}"] for column in columns} for i in range(count)]


class FakeSession:
    def __init__(self, rows: list[db.TravelTime]) -> None:
        self.rows = rows
        self.selects: list[Any] = []
        self.executed: list[Any] = []

    async def scalars(self, statement: Any) -> list[db.TravelTime]:
        self.selects.append(statement)
        return list(self.rows)

    async def execute(self, statement: Any) -> None:
        self.executed.append(statement)


class MapboxStub:
    """Answers the Matrix API with `durations`/`distances` for the requested destinations."""

    def __init__(self, routes: dict[int, tuple[float | None, float | None]]) -> None:
        # Keyed by destination position within the request (0-based).
        self.routes = routes
        self.requests: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        count = len(request.url.params["destinations"].split(";"))
        pairs = [self.routes.get(i, (None, None)) for i in range(count)]
        body = {
            "code": "Ok",
            "durations": [[seconds for seconds, _ in pairs]],
            "distances": [[meters for _, meters in pairs]],
        }
        return httpx.Response(200, json=body)


def client(handler: Any, token: str = TOKEN) -> MapboxClient:
    return MapboxClient(token=token, transport=httpx.MockTransport(handler))


def failing(request: httpx.Request) -> httpx.Response:
    raise AssertionError(f"Mapbox must not be called: {request.url.path}")


class TestHelpers:
    def test_haversine_is_zero_for_the_same_point(self) -> None:
        assert haversine_meters((37.0, -122.0), (37.0, -122.0)) == 0

    def test_haversine_one_degree_of_latitude(self) -> None:
        assert haversine_meters((37.0, -122.0), (38.0, -122.0)) == pytest.approx(111_195, rel=1e-3)

    def test_fallback_is_six_plus_two_point_three_per_mile(self) -> None:
        assert fallback_minutes(0) == 6
        assert fallback_minutes(10 * 1609.344) == pytest.approx(29.0)

    @pytest.mark.parametrize(
        ("provider", "age", "fresh"),
        [
            ("mapbox", timedelta(days=29, hours=23), True),
            ("mapbox", MAPBOX_MAX_AGE, False),
            ("haversine_fallback", timedelta(minutes=59), True),
            ("haversine_fallback", FALLBACK_MAX_AGE, False),
        ],
    )
    def test_freshness_by_provider(self, provider: str, age: timedelta, fresh: bool) -> None:
        assert is_fresh(cached(1, "10", provider, age), NOW) is fresh


class TestMapboxClient:
    async def test_requests_one_source_and_all_destinations(self) -> None:
        stub = MapboxStub({0: (600.0, 9000.0), 1: (1200.0, None)})

        routes = await client(stub).routes((37.5, -122.2), [(37.4, -122.1), (37.8, -122.4)])

        assert routes == [Route(600.0, 9000.0), Route(1200.0, None)]
        (request,) = stub.requests
        assert request.url.path == (
            "/directions-matrix/v1/mapbox/driving/"
            "-122.200000,37.500000;-122.100000,37.400000;-122.400000,37.800000"
        )
        assert request.url.params["sources"] == "0"
        assert request.url.params["destinations"] == "1;2"
        assert request.url.params["annotations"] == "duration,distance"
        assert request.url.params["access_token"] == TOKEN

    async def test_unroutable_destination_is_none(self) -> None:
        stub = MapboxStub({1: (300.0, 4000.0)})
        routes = await client(stub).routes((37.5, -122.2), [(37.4, -122.1), (37.8, -122.4)])
        assert routes == [None, Route(300.0, 4000.0)]

    async def test_splits_more_than_24_destinations(self) -> None:
        stub = MapboxStub({0: (60.0, 1000.0)})
        destinations = [(37.0 + i / 100, -122.0) for i in range(30)]

        routes = await client(stub).routes((37.5, -122.2), destinations)

        assert len(routes) == 30
        assert [len(r.url.params["destinations"].split(";")) for r in stub.requests] == [24, 6]

    async def test_no_destinations_makes_no_request(self) -> None:
        assert await client(failing).routes((37.5, -122.2), []) == []

    @pytest.mark.parametrize(
        "response",
        [
            httpx.Response(500),
            httpx.Response(401, json={"message": "Not Authorized"}),
            httpx.Response(200, json={"code": "InvalidInput"}),
            httpx.Response(200, json={"code": "Ok", "durations": [[1.0]]}),
            httpx.Response(200, content=b"not json"),
            httpx.Response(200, json=["Ok"]),
        ],
    )
    async def test_bad_responses_raise_mapbox_error(self, response: httpx.Response) -> None:
        with pytest.raises(MapboxError):
            await client(lambda _: response).routes((37.5, -122.2), [(1, 1), (2, 2)])

    async def test_timeout_raises_mapbox_error_without_the_token(self) -> None:
        def timeout(request: httpx.Request) -> httpx.Response:
            raise httpx.ReadTimeout("timed out", request=request)

        with pytest.raises(MapboxError) as raised:
            await client(timeout).routes((37.5, -122.2), [(37.4, -122.1)])
        assert TOKEN not in str(raised.value)

    def test_get_mapbox_client_uses_the_configured_token(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        class FakeSettings:
            mapbox_token = TOKEN

        monkeypatch.setattr("app.services.travel.get_settings", FakeSettings)
        get_mapbox_client.cache_clear()
        try:
            assert get_mapbox_client() == MapboxClient(token=TOKEN)
        finally:
            get_mapbox_client.cache_clear()

    def test_empty_token_is_not_configured(self) -> None:
        assert not MapboxClient(token="").configured
        assert MapboxClient(token=TOKEN).configured


class TestTravelMinutes:
    async def test_no_gyms_does_nothing(self) -> None:
        session = FakeSession([])
        result = await travel_minutes(session, LOCATION, [], mapbox=client(failing), now=NOW)  # type: ignore[arg-type]
        assert result == {}
        assert session.selects == session.executed == []

    async def test_fresh_cache_makes_no_request_and_no_write(self) -> None:
        session = FakeSession(
            [
                cached(1, "12.50", "mapbox", timedelta(days=29)),
                cached(2, "40.00", "mapbox", timedelta(days=1)),
                cached(3, "30.25", "haversine_fallback", timedelta(minutes=30)),
            ]
        )

        result = await travel_minutes(session, LOCATION, GYMS, mapbox=client(failing), now=NOW)  # type: ignore[arg-type]

        assert result == {
            1: TravelEstimate(12.5, "mapbox"),
            2: TravelEstimate(40.0, "mapbox"),
            3: TravelEstimate(30.25, "haversine_fallback"),
        }
        assert session.executed == []
        select_sql = sql(session.selects[0])
        assert "from travel_times" in select_sql
        assert "travel_times.location_id =" in select_sql
        assert "travel_times.gym_id in" in select_sql

    async def test_fetches_only_missing_and_stale_pairs_in_one_request(self) -> None:
        session = FakeSession(
            [
                cached(1, "12.50", "mapbox", timedelta(days=2)),  # fresh
                cached(2, "40.00", "mapbox", timedelta(days=31)),  # stale
                # gym 3: missing
            ]
        )
        stub = MapboxStub({0: (2100.0, 52_000.4), 1: (1830.0, 45_000.6)})

        result = await travel_minutes(session, LOCATION, GYMS, mapbox=client(stub), now=NOW)  # type: ignore[arg-type]

        (request,) = stub.requests
        assert request.url.params["destinations"] == "1;2"
        assert "-122.419400,37.774900;-122.271200,37.804400" in request.url.path
        assert result == {
            1: TravelEstimate(12.5, "mapbox"),
            2: TravelEstimate(35.0, "mapbox"),
            3: TravelEstimate(30.5, "mapbox"),
        }
        (upsert,) = session.executed
        upsert_sql = sql(upsert)
        assert "insert into travel_times" in upsert_sql
        assert "on conflict (location_id, gym_id) do update" in upsert_sql
        assert upserted(upsert) == [
            {
                "location_id": LOCATION_ID,
                "gym_id": 2,
                "minutes": Decimal("35.00"),
                "meters": 52_000,
                "provider": "mapbox",
                "computed_at": NOW,
            },
            {
                "location_id": LOCATION_ID,
                "gym_id": 3,
                "minutes": Decimal("30.50"),
                "meters": 45_001,
                "provider": "mapbox",
                "computed_at": NOW,
            },
        ]

    async def test_stale_fallback_row_is_retried_with_mapbox(self) -> None:
        session = FakeSession([cached(1, "20.00", "haversine_fallback", timedelta(hours=2))])
        stub = MapboxStub({0: (900.0, 15_000.0)})

        result = await travel_minutes(session, LOCATION, GYMS[:1], mapbox=client(stub), now=NOW)  # type: ignore[arg-type]

        assert result == {1: TravelEstimate(15.0, "mapbox")}
        assert len(stub.requests) == 1

    @pytest.mark.parametrize(
        "mapbox",
        [
            client(lambda _: httpx.Response(500)),
            client(failing, token=""),
        ],
        ids=["mapbox-500", "no-token"],
    )
    async def test_falls_back_to_haversine_and_writes_it(self, mapbox: MapboxClient) -> None:
        session = FakeSession([cached(1, "12.50", "mapbox", timedelta(days=40))])

        result = await travel_minutes(session, LOCATION, GYMS, mapbox=mapbox, now=NOW)  # type: ignore[arg-type]

        origin = (LOCATION.latitude, LOCATION.longitude)
        for g in GYMS:
            expected = fallback_minutes(haversine_meters(origin, (g.latitude, g.longitude)))
            estimate = result[g.id]
            assert estimate.provider == "haversine_fallback"
            assert estimate.minutes == pytest.approx(expected, abs=0.005)
        rows = upserted(session.executed[0])
        assert [row["gym_id"] for row in rows] == [1, 2, 3]
        assert {row["provider"] for row in rows} == {"haversine_fallback"}
        assert {row["meters"] for row in rows} == {None}
        assert {row["computed_at"] for row in rows} == {NOW}

    async def test_unroutable_gym_gets_the_fallback_others_mapbox(self) -> None:
        session = FakeSession([])
        stub = MapboxStub({0: (600.0, 8000.0), 2: (1200.0, 20_000.0)})

        result = await travel_minutes(session, LOCATION, GYMS, mapbox=client(stub), now=NOW)  # type: ignore[arg-type]

        assert result[1] == TravelEstimate(10.0, "mapbox")
        assert result[2].provider == "haversine_fallback"
        assert result[3] == TravelEstimate(20.0, "mapbox")
        assert [row["provider"] for row in upserted(session.executed[0])] == [
            "mapbox",
            "haversine_fallback",
            "mapbox",
        ]

    async def test_minutes_are_clamped_to_the_column(self) -> None:
        session = FakeSession([])
        stub = MapboxStub({0: (10_000_000.0, 1.0)})

        result = await travel_minutes(session, LOCATION, GYMS[:1], mapbox=client(stub), now=NOW)  # type: ignore[arg-type]

        assert result[1] == TravelEstimate(9999.99, "mapbox")

    async def test_defaults_now_to_the_wall_clock(self) -> None:
        session = FakeSession([])
        before = datetime.now(UTC)

        await travel_minutes(session, LOCATION, GYMS[:1], mapbox=client(failing, token=""))  # type: ignore[arg-type]

        (row,) = upserted(session.executed[0])
        assert row["computed_at"] >= before


def test_stub_body_is_valid_json() -> None:
    # Guards the stub itself: a MockTransport handler error would surface as MapboxError.
    request = httpx.Request("GET", "https://example.test/?destinations=1;2")
    body = json.loads(MapboxStub({0: (1.0, 2.0)})(request).content)
    assert body["durations"] == [[1.0, None]]
