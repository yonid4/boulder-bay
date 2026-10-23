"""`GET /api/rankings`, run through the real service against a fake session.

Only the session, the user, the settings and the Mapbox client are overridden, so these
cover the route, `services/ranking.py`'s `rank_gyms`, and how it drives the busyness loader,
travel times and prefs together.
"""

from collections.abc import Iterator, Sequence
from datetime import UTC, datetime, time, timedelta
from decimal import Decimal
from typing import Any
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Insert
from sqlalchemy.dialects import postgresql

from app.api.dependencies import AuthenticatedUser, get_session, require_user
from app.config import Settings, get_settings
from app.db import models as db
from app.main import app
from app.services.travel import MapboxClient, fallback_minutes, get_mapbox_client, haversine_meters

USER_ID = UUID("0e17b0e8-660c-46ef-ab9f-c4d91340809d")
HOME_ID = UUID("d16878be-c4bc-462f-8929-c464b6a5efad")
WORK_ID = UUID("5b0f9f4e-7a39-4d0e-9a53-2f7c1f8a6b21")
LA = "America/Los_Angeles"
# Monday 2026-09-14, noon in Los Angeles: long finished, so with no snapshots every open
# gym resolves from its curve row.
AT = "2026-09-14T12:00:00-07:00"
RADIUS_METERS = 12_345


def location_row(
    location_id: UUID = HOME_ID, *, label: str = "Home", kind: str = "home", is_default: bool = True
) -> dict[str, Any]:
    return {
        "id": location_id,
        "label": label,
        "address": "Redwood City, CA",
        "latitude": 37.4852,
        "longitude": -122.2364,
        "is_default": is_default,
        "kind": kind,
    }


def gym_row(gym_id: int, name: str, latitude: float, longitude: float) -> db.Gym:
    return db.Gym(
        id=gym_id,
        slug=name.lower().replace(" ", "-"),
        name=name,
        brand="touchstone",
        city="San Francisco",
        latitude=latitude,
        longitude=longitude,
        timezone=LA,
        logo_id=gym_id,
        is_active=True,
    )


def open_all_week(gym_id: int) -> list[db.GymHours]:
    return [
        db.GymHours(gym_id=gym_id, day_of_week=day, opens_at=time(6), closes_at=time(22))
        for day in range(7)
    ]


def curve(gym_id: int, busy_pct: int) -> db.BusynessCurve:
    # Monday is 1, matching `local_slot`; the loader keys rows by gym only.
    return db.BusynessCurve(gym_id=gym_id, day_of_week=1, hour_of_day=12, busy_pct=busy_pct)


def travel(gym_id: int, minutes: str) -> db.TravelTime:
    return db.TravelTime(
        location_id=HOME_ID,
        gym_id=gym_id,
        minutes=Decimal(minutes),
        meters=None,
        provider="mapbox",
        computed_at=datetime.now(UTC) - timedelta(minutes=5),
    )


DOGPATCH = gym_row(1, "Dogpatch Boulders", 37.7567, -122.3903)
MISSION = gym_row(2, "Mission Cliffs", 37.7614, -122.4127)
IRONWORKS = gym_row(3, "Berkeley Ironworks", 37.8513, -122.2913)
GREAT_WESTERN = gym_row(4, "Great Western Power", 37.8199, -122.2783)

# Default weights: 100 - 0.6 * crowd - 0.5 * min(travel, 60) + 15 member - 60 closed.
#   Mission Cliffs       20% busy, 30 min           -> 100 - 12 - 15      = 73
#   Berkeley Ironworks   50% busy, 20 min           -> 100 - 30 - 10      = 60
#   Dogpatch Boulders    70% busy, 30 min, member   -> 100 - 42 - 15 + 15 = 58
#   Great Western Power  closed (no hours), 10 min  -> 100 - 0 - 5 - 60   = 35
GYMS = [DOGPATCH, MISSION, IRONWORKS, GREAT_WESTERN]
HOURS = [*open_all_week(1), *open_all_week(2), *open_all_week(3)]
CURVES = [curve(1, 70), curve(2, 20), curve(3, 50)]
TRAVEL = [travel(1, "30"), travel(2, "30"), travel(3, "20"), travel(4, "10")]


class FakeResult:
    def __init__(self, rows: Sequence[Any]) -> None:
        self.rows = list(rows)

    def __iter__(self) -> Iterator[Any]:
        return iter(self.rows)

    def mappings(self) -> "FakeResult":
        return self

    def all(self) -> list[Any]:
        return list(self.rows)

    def first(self) -> Any:
        return self.rows[0] if self.rows else None

    def one(self) -> Any:
        assert len(self.rows) == 1
        return self.rows[0]

    def one_or_none(self) -> Any:
        assert len(self.rows) <= 1
        return self.rows[0] if self.rows else None


def table_of(statement: Any) -> str:
    if isinstance(statement, Insert):
        return f"insert {statement.table.name}"
    return str(statement.get_final_froms()[0].name)


def sql(statement: Any) -> str:
    return str(statement.compile(dialect=postgresql.dialect())).lower()


def params(statement: Any) -> set[Any]:
    return set(statement.compile(dialect=postgresql.dialect()).params.values())


class FakeSession:
    """Answers each query by the table it reads, the way the database would for one user."""

    def __init__(
        self,
        *,
        locations: Sequence[dict[str, Any]] = (location_row(),),
        gyms: Sequence[db.Gym] = GYMS,
        hours: Sequence[db.GymHours] = HOURS,
        curves: Sequence[db.BusynessCurve] = CURVES,
        member_ids: Sequence[int] = (1,),
        travel_rows: Sequence[db.TravelTime] = TRAVEL,
    ) -> None:
        self.answers: dict[str, Sequence[Any]] = {
            "saved_locations": locations,
            "gyms": gyms,
            "gym_hours": hours,
            "busyness_curves": curves,
            "busyness_snapshots": [],
            "gym_memberships": member_ids,
            "ranking_prefs": [db.RankingPrefs(**PREFS)],
            "travel_times": travel_rows,
        }
        self.statements: list[Any] = []
        # Reads, writes and commits in the order they happened.
        self.events: list[str] = []

    def answer(self, statement: Any) -> FakeResult:
        self.statements.append(statement)
        table = table_of(statement)
        self.events.append(table)
        return FakeResult(self.answers.get(table, []))

    async def execute(self, statement: Any) -> FakeResult:
        return self.answer(statement)

    async def scalars(self, statement: Any) -> FakeResult:
        return self.answer(statement)

    async def commit(self) -> None:
        self.events.append("commit")

    def statement_for(self, table: str) -> Any:
        return next(s for s in self.statements if table_of(s) == table)


PREFS: dict[str, Any] = {
    "user_id": USER_ID,
    "w_crowd": Decimal("0.6"),
    "w_travel": Decimal("0.5"),
    "member_boost": Decimal("15"),
    "closed_penalty": Decimal("60"),
    "travel_cap_minutes": 60,
}


def failing(request: httpx.Request) -> httpx.Response:
    raise AssertionError(f"Mapbox must not be called: {request.url.path}")


class Harness:
    def __init__(self) -> None:
        self.session = FakeSession()
        self.mapbox = MapboxClient(token="", transport=httpx.MockTransport(failing))


@pytest.fixture
def harness() -> Iterator[Harness]:
    state = Harness()

    async def fake_user() -> AuthenticatedUser:
        return AuthenticatedUser(id=USER_ID)

    async def fake_session() -> FakeSession:
        return state.session

    def fake_settings() -> Settings:
        return Settings(
            _env_file=None,  # type: ignore[call-arg]
            database_url="postgresql+asyncpg://user:pass@localhost:5432/postgres",
            supabase_url="https://example.supabase.co",
            ranking_radius_meters=RADIUS_METERS,
        )

    app.dependency_overrides[require_user] = fake_user
    app.dependency_overrides[get_session] = fake_session
    app.dependency_overrides[get_settings] = fake_settings
    app.dependency_overrides[get_mapbox_client] = lambda: state.mapbox
    try:
        yield state
    finally:
        app.dependency_overrides.clear()


def get(params: dict[str, Any] | None = None) -> httpx.Response:
    return TestClient(app).get("/api/rankings", params={"at": AT, **(params or {})})


class TestRanking:
    def test_ranks_gyms_by_score_with_travel_and_membership(self, harness: Harness) -> None:
        response = get({"location_id": str(HOME_ID)})

        assert response.status_code == 200
        data = response.json()["data"]
        assert set(data) == {"at", "location", "ranked_gyms"}
        assert data["at"] == AT
        assert data["location"] == {
            "id": str(HOME_ID),
            "label": "Home",
            "address": "Redwood City, CA",
            "latitude": 37.4852,
            "longitude": -122.2364,
            "is_default": True,
            "kind": "home",
        }
        ranked = data["ranked_gyms"]
        assert [r["gym"]["slug"] for r in ranked] == [
            "mission-cliffs",
            "berkeley-ironworks",
            "dogpatch-boulders",
            "great-western-power",
        ]
        assert [r["rank"] for r in ranked] == [1, 2, 3, 4]
        assert [r["score"] for r in ranked] == pytest.approx([73.0, 60.0, 58.0, 35.0])
        assert [r["travel_minutes"] for r in ranked] == [30.0, 20.0, 30.0, 10.0]
        assert set(ranked[0]) == {"rank", "score", "travel_minutes", "gym"}
        assert [r["gym"]["is_member"] for r in ranked] == [False, False, True, False]
        assert ranked[2]["gym"]["busyness"] == {
            "at": AT,
            "is_open": True,
            "busy_pct": 70,
            "level": "packed",
            "source": "forecast",
        }
        assert ranked[3]["gym"]["busyness"]["is_open"] is False
        assert ranked[0]["gym"]["logo_url"] == "http://testserver/api/gyms/mission-cliffs/logo"

    def test_scopes_the_location_to_the_caller(self, harness: Harness) -> None:
        get({"location_id": str(HOME_ID)})

        lookup = harness.session.statement_for("saved_locations")
        assert params(lookup) >= {USER_ID, HOME_ID}

    def test_uses_the_default_location_when_none_is_given(self, harness: Harness) -> None:
        harness.session = FakeSession(
            locations=[location_row(WORK_ID, label="Office", kind="work")]
        )

        response = get()

        assert response.status_code == 200
        assert response.json()["data"]["location"]["id"] == str(WORK_ID)
        lookup = harness.session.statement_for("saved_locations")
        assert "order by saved_locations.is_default desc" in sql(lookup)
        assert USER_ID in params(lookup)

    def test_unknown_or_another_users_location_is_404(self, harness: Harness) -> None:
        harness.session = FakeSession(locations=[])

        response = get({"location_id": str(HOME_ID)})

        assert response.status_code == 404
        assert response.json() == {"detail": "Location not found"}
        assert "commit" not in harness.session.events

    def test_a_user_with_no_locations_is_409(self, harness: Harness) -> None:
        harness.session = FakeSession(locations=[])

        response = get()

        assert response.status_code == 409
        assert response.json() == {"detail": "A saved location is required"}
        assert "commit" not in harness.session.events

    def test_a_naive_at_is_422_before_any_query(self, harness: Harness) -> None:
        response = TestClient(app).get("/api/rankings", params={"at": "2026-09-14T12:00:00"})

        assert response.status_code == 422
        assert "timezone" in response.json()["detail"]
        assert harness.session.statements == []

    def test_a_malformed_location_id_is_422(self, harness: Harness) -> None:
        assert get({"location_id": "not-a-uuid"}).status_code == 422

    def test_at_defaults_to_now(self, harness: Harness) -> None:
        before = datetime.now(UTC)

        response = TestClient(app).get("/api/rankings")

        assert response.status_code == 200
        at = datetime.fromisoformat(response.json()["data"]["at"])
        assert before <= at <= datetime.now(UTC)

    def test_limit_keeps_the_top_gyms(self, harness: Harness) -> None:
        response = get({"limit": 2})

        ranked = response.json()["data"]["ranked_gyms"]
        assert [r["gym"]["slug"] for r in ranked] == ["mission-cliffs", "berkeley-ironworks"]
        assert [r["rank"] for r in ranked] == [1, 2]

    def test_a_tie_goes_to_the_name_a_to_z(self, harness: Harness) -> None:
        zeta = gym_row(1, "Zeta Climbing", 37.7567, -122.3903)
        alpha = gym_row(2, "Alpha Boulders", 37.7614, -122.4127)
        harness.session = FakeSession(
            gyms=[zeta, alpha],
            curves=[curve(1, 40), curve(2, 40)],
            member_ids=[],
            travel_rows=[travel(1, "25"), travel(2, "25")],
        )

        ranked = get().json()["data"]["ranked_gyms"]

        assert [r["gym"]["name"] for r in ranked] == ["Alpha Boulders", "Zeta Climbing"]
        assert ranked[0]["score"] == ranked[1]["score"]

    def test_weights_come_from_the_callers_prefs(self, harness: Harness) -> None:
        boosted = {**PREFS, "member_boost": Decimal("100")}
        harness.session.answers["ranking_prefs"] = [db.RankingPrefs(**boosted)]

        ranked = get().json()["data"]["ranked_gyms"]

        assert ranked[0]["gym"]["slug"] == "dogpatch-boulders"
        assert ranked[0]["score"] == pytest.approx(143.0)

    def test_prefilters_active_gyms_within_the_radius(self, harness: Harness) -> None:
        get()

        query = sql(harness.session.statement_for("gyms"))
        assert "extensions.st_dwithin(gyms.geog, extensions.geography(" in query
        assert "extensions.st_makepoint(" in query
        assert "gyms.is_active" in query
        assert "st_distance" not in query
        assert {RADIUS_METERS, 37.4852, -122.2364} <= params(harness.session.statement_for("gyms"))

    def test_creates_prefs_and_writes_travel_then_commits_once(self, harness: Harness) -> None:
        harness.session = FakeSession(travel_rows=[])

        get()

        events = harness.session.events
        assert events.count("commit") == 1
        assert events[-1] == "commit"
        assert "insert ranking_prefs" in events
        assert "insert travel_times" in events

    def test_no_gyms_in_range_is_an_empty_list(self, harness: Harness) -> None:
        harness.session = FakeSession(gyms=[])

        response = get()

        assert response.status_code == 200
        assert response.json()["data"]["ranked_gyms"] == []
        events = harness.session.events
        assert "travel_times" not in events
        # The prefs row may have been created, so this still commits.
        assert events[-1] == "commit"

    def test_still_requires_auth(self, client: TestClient) -> None:
        assert client.get("/api/rankings").status_code == 401


class TestTravelProviders:
    def test_no_token_uses_the_straight_line_fallback(self, harness: Harness) -> None:
        harness.session = FakeSession(travel_rows=[])

        response = get()

        assert response.status_code == 200
        by_slug = {r["gym"]["slug"]: r for r in response.json()["data"]["ranked_gyms"]}
        origin = (37.4852, -122.2364)
        expected = fallback_minutes(haversine_meters(origin, (MISSION.latitude, MISSION.longitude)))
        assert by_slug["mission-cliffs"]["travel_minutes"] == pytest.approx(expected, abs=0.005)
        upsert = sql(harness.session.statement_for("insert travel_times"))
        assert "on conflict" in upsert
        assert "haversine_fallback" in params(harness.session.statement_for("insert travel_times"))

    def test_a_mapbox_client_supplies_driving_times(self, harness: Harness) -> None:
        requests: list[httpx.Request] = []

        def matrix(request: httpx.Request) -> httpx.Response:
            requests.append(request)
            count = len(request.url.params["destinations"].split(";"))
            # Destination i drives in (i + 1) * 10 minutes.
            body = {
                "code": "Ok",
                "durations": [[(i + 1) * 600.0 for i in range(count)]],
                "distances": [[(i + 1) * 9000.0 for i in range(count)]],
            }
            return httpx.Response(200, json=body)

        harness.session = FakeSession(travel_rows=[])
        harness.mapbox = MapboxClient(token="pk.test", transport=httpx.MockTransport(matrix))

        response = get()

        assert response.status_code == 200
        assert len(requests) == 1
        by_slug = {r["gym"]["slug"]: r for r in response.json()["data"]["ranked_gyms"]}
        # Gyms reach Mapbox in prefilter order: Dogpatch, Mission, Ironworks, Great Western.
        assert by_slug["dogpatch-boulders"]["travel_minutes"] == 10.0
        assert by_slug["great-western-power"]["travel_minutes"] == 40.0
        assert "mapbox" in params(harness.session.statement_for("insert travel_times"))
