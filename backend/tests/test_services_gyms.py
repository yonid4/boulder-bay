from collections.abc import Sequence
from datetime import UTC, datetime, time, timedelta
from typing import Any
from uuid import UUID

import pytest
from sqlalchemy.dialects import postgresql

from app.api.models import BusynessLevel, BusynessSource, GymBrand, ResolvedBusyness
from app.db import models as db
from app.services.busyness import resolve_busyness
from app.services.gyms import (
    GymLogoImage,
    get_gym_logo,
    list_gyms,
    load_busyness_inputs,
    to_api_gym,
)

LA = "America/Los_Angeles"
USER_ID = UUID("7878e808-a48f-4649-8a65-3feb6029a591")


def gym_row(**overrides: Any) -> db.Gym:
    values: dict[str, Any] = {
        "id": 1,
        "slug": "dogpatch",
        "name": "Dogpatch Boulders",
        "brand": "touchstone",
        "city": "San Francisco",
        "latitude": 37.7567,
        "longitude": -122.3903,
        "timezone": LA,
        "google_maps_query": "Dogpatch Boulders San Francisco",
        "logo_id": 3,
        "is_active": True,
    }
    values.update(overrides)
    return db.Gym(**values)


def hours_row(gym_id: int, day: int, opens: time, closes: time) -> db.GymHours:
    return db.GymHours(gym_id=gym_id, day_of_week=day, opens_at=opens, closes_at=closes)


# Sunday 2026-09-13 through Saturday 2026-09-19, 06:00-22:00 local.
WEEK = [hours_row(1, day, time(6), time(22)) for day in range(7)]


class FakeSession:
    """Answers `scalars()` calls in order with canned rows."""

    def __init__(self, *results: Sequence[Any]) -> None:
        self.results = list(results)
        self.statements: list[Any] = []

    async def scalars(self, statement: Any) -> Any:
        self.statements.append(statement)
        rows = self.results.pop(0)

        class Result:
            def all(self) -> list[Any]:
                return list(rows)

        return Result()


class TestToApiGym:
    def test_maps_columns_and_passes_busyness_through(self) -> None:
        at = datetime(2026, 9, 14, 19, tzinfo=UTC)
        busyness = ResolvedBusyness(at=at, is_open=True, busy_pct=35, level=BusynessLevel.QUIET)

        gym = to_api_gym(gym_row(), busyness=busyness, is_member=False)

        assert gym.slug == "dogpatch"
        assert gym.name == "Dogpatch Boulders"
        assert gym.brand is GymBrand.TOUCHSTONE
        assert gym.city == "San Francisco"
        assert gym.latitude == 37.7567
        assert gym.longitude == -122.3903
        assert gym.logo_url is None
        assert gym.busyness == busyness
        assert gym.is_member is False

    def test_carries_the_membership_flag(self) -> None:
        at = datetime(2026, 9, 14, 19, tzinfo=UTC)

        gym = to_api_gym(gym_row(), busyness=ResolvedBusyness(at=at, is_open=True), is_member=True)

        assert gym.is_member is True

    def test_fills_logo_url_when_the_gym_has_a_logo(self) -> None:
        at = datetime(2026, 9, 14, 19, tzinfo=UTC)

        gym = to_api_gym(
            gym_row(),
            busyness=ResolvedBusyness(at=at, is_open=True),
            is_member=False,
            logo_url_for=lambda slug: f"http://testserver/api/gyms/{slug}/logo",
        )

        assert str(gym.logo_url) == "http://testserver/api/gyms/dogpatch/logo"

    def test_leaves_logo_url_empty_when_the_gym_has_no_logo(self) -> None:
        at = datetime(2026, 9, 14, 19, tzinfo=UTC)

        gym = to_api_gym(
            gym_row(logo_id=None),
            busyness=ResolvedBusyness(at=at, is_open=True),
            is_member=False,
            logo_url_for=lambda slug: f"http://testserver/api/gyms/{slug}/logo",
        )

        assert gym.logo_url is None


class FakeExecuteSession:
    """Answers one `execute()` call with a single canned row, or none."""

    def __init__(self, row: tuple[bytes, str, str] | None) -> None:
        self.row = row
        self.statements: list[Any] = []

    async def execute(self, statement: Any) -> Any:
        self.statements.append(statement)
        row = self.row

        class Result:
            def one_or_none(self) -> tuple[bytes, str, str] | None:
                return row

        return Result()


class TestGetGymLogo:
    async def test_returns_the_logo_bytes_type_and_hash(self) -> None:
        session = FakeExecuteSession((b"png", "image/png", "ab12"))

        logo = await get_gym_logo(session, "dogpatch")  # type: ignore[arg-type]

        assert logo == GymLogoImage(image=b"png", content_type="image/png", sha256="ab12")

    async def test_returns_none_for_an_unknown_slug_or_a_gym_without_a_logo(self) -> None:
        assert await get_gym_logo(FakeExecuteSession(None), "nope") is None  # type: ignore[arg-type]

    async def test_runs_one_query_joined_through_the_gyms_logo_id(self) -> None:
        session = FakeExecuteSession(None)

        await get_gym_logo(session, "dogpatch")  # type: ignore[arg-type]

        assert len(session.statements) == 1
        sql = str(session.statements[0].compile(dialect=postgresql.dialect()))
        assert "gyms.logo_id = gym_logos.id" in sql
        assert "gyms.slug" in sql


def curve_row(gym_id: int, day: int, hour: int, pct: int) -> db.BusynessCurve:
    return db.BusynessCurve(gym_id=gym_id, day_of_week=day, hour_of_day=hour, busy_pct=pct)


def snapshot_row(gym_id: int, observed_at: datetime, live_pct: int | None) -> db.BusynessSnapshot:
    return db.BusynessSnapshot(
        gym_id=gym_id, observed_at=observed_at, live_pct=live_pct, typical_pct=30
    )


# Monday 2026-09-14 12:00 PDT, and ten minutes later by the wall clock.
MONDAY_NOON = datetime(2026, 9, 14, 19, tzinfo=UTC)
NOW = MONDAY_NOON + timedelta(minutes=10)


class TestListGyms:
    async def test_resolves_each_gym_from_hours_snapshots_and_curves(self) -> None:
        gyms = [
            gym_row(id=1, slug="dogpatch", name="Dogpatch Boulders"),
            gym_row(id=2, slug="mission", name="Mission Cliffs"),
            gym_row(id=3, slug="mosaic", name="Mosaic Boulders", brand="independent"),
            gym_row(id=4, slug="pipe", name="Pacific Pipe", brand="independent"),
        ]
        hours = [
            hours_row(1, 1, time(6), time(22)),
            hours_row(2, 1, time(6), time(22)),
            hours_row(3, 1, time(13), time(23)),
            hours_row(4, 1, time(6), time(22)),
        ]
        curves = [curve_row(1, 1, 12, 45), curve_row(2, 1, 12, 75)]
        snapshots = [snapshot_row(1, MONDAY_NOON, 20)]
        session = FakeSession(gyms, hours, curves, snapshots, [2, 3])

        result = await list_gyms(session, user_id=USER_ID, at=MONDAY_NOON, now=NOW)  # type: ignore[arg-type]

        assert [gym.is_member for gym in result] == [False, True, True, False]
        dogpatch, mission, mosaic, pipe = (gym.busyness for gym in result)
        assert (dogpatch.source, dogpatch.busy_pct, dogpatch.level) == (
            BusynessSource.LIVE,
            20,
            BusynessLevel.QUIET,
        )
        assert (mission.source, mission.busy_pct, mission.level) == (
            BusynessSource.FORECAST,
            75,
            BusynessLevel.PACKED,
        )
        assert mosaic.is_open is False
        assert mosaic.busy_pct is None
        assert pipe.is_open is True
        assert pipe.busy_pct is None
        assert result[2].brand is GymBrand.INDEPENDENT
        assert len(session.statements) == 5

    async def test_loads_only_the_callers_memberships_in_one_query(self) -> None:
        session = FakeSession([gym_row()], WEEK, [], [], [1])

        result = await list_gyms(session, user_id=USER_ID, at=MONDAY_NOON, now=NOW)  # type: ignore[arg-type]

        assert result[0].is_member is True
        compiled = session.statements[4].compile(dialect=postgresql.dialect())
        assert "gym_memberships.user_id" in str(compiled)
        assert USER_ID in compiled.params.values()

    async def test_filters_curves_to_each_gyms_local_hour(self) -> None:
        session = FakeSession([gym_row()], WEEK, [], [], [])

        await list_gyms(session, user_id=USER_ID, at=MONDAY_NOON, now=NOW)  # type: ignore[arg-type]

        curve_sql = str(session.statements[2].compile(dialect=postgresql.dialect()))
        columns = "busyness_curves.gym_id, busyness_curves.day_of_week, busyness_curves.hour_of_day"
        assert f"({columns}) IN" in curve_sql
        params = session.statements[2].compile(dialect=postgresql.dialect()).params
        assert (1, 1, 12) in next(iter(params.values()))

    async def test_fetches_snapshots_in_the_live_window_or_the_requested_hour(self) -> None:
        session = FakeSession([gym_row()], WEEK, [], [], [])
        at = MONDAY_NOON - timedelta(hours=2, minutes=-15)  # 10:15 PDT, an hour that is over

        await list_gyms(session, user_id=USER_ID, at=at, now=NOW)  # type: ignore[arg-type]

        compiled = session.statements[3].compile(dialect=postgresql.dialect())
        assert "DISTINCT" not in str(compiled)
        params = list(compiled.params.values())
        assert NOW - timedelta(minutes=45) in params
        assert NOW in params
        ten_am = MONDAY_NOON - timedelta(hours=2)
        assert ten_am in params
        assert ten_am + timedelta(hours=1) in params

    async def test_averages_a_finished_hour_and_keeps_live_for_now(self) -> None:
        gyms = [
            gym_row(id=1, slug="dogpatch", name="Dogpatch Boulders"),
            gym_row(id=2, slug="mission", name="Mission Cliffs"),
        ]
        hours = [hours_row(1, 1, time(6), time(22)), hours_row(2, 1, time(6), time(22))]
        eleven_am = MONDAY_NOON - timedelta(hours=1)
        curves = [curve_row(1, 1, 11, 45), curve_row(2, 1, 11, 75)]
        snapshots = [
            snapshot_row(1, eleven_am, 30),
            snapshot_row(1, eleven_am + timedelta(minutes=30), 50),
            snapshot_row(1, MONDAY_NOON, 90),
        ]
        session = FakeSession(gyms, hours, curves, snapshots, [])

        result = await list_gyms(session, user_id=USER_ID, at=eleven_am, now=NOW)  # type: ignore[arg-type]

        dogpatch, mission = (gym.busyness for gym in result)
        assert (dogpatch.source, dogpatch.busy_pct) == (BusynessSource.OBSERVED, 40)
        assert (mission.source, mission.busy_pct) == (BusynessSource.FORECAST, 75)

    async def test_defaults_at_to_now_in_utc(self) -> None:
        before = datetime.now(UTC)
        session = FakeSession([gym_row()], WEEK, [], [], [])

        result = await list_gyms(session, user_id=USER_ID)  # type: ignore[arg-type]

        assert result[0].busyness.at.tzinfo is not None
        assert before <= result[0].busyness.at <= datetime.now(UTC)

    async def test_rejects_naive_at(self) -> None:
        session = FakeSession([gym_row()], WEEK, [], [], [])

        with pytest.raises(ValueError, match="timezone"):
            await list_gyms(session, user_id=USER_ID, at=datetime(2026, 9, 14, 12))  # type: ignore[arg-type]
        assert session.statements == []

    async def test_skips_the_other_queries_when_there_are_no_gyms(self) -> None:
        session = FakeSession([])

        assert await list_gyms(session, user_id=USER_ID, at=datetime(2026, 9, 14, tzinfo=UTC)) == []  # type: ignore[arg-type]
        assert len(session.statements) == 1


class TestLoadBusynessInputs:
    async def test_takes_three_queries_however_many_gyms(self) -> None:
        gyms = [gym_row(id=i, slug=f"gym-{i}", name=f"Gym {i}") for i in range(1, 17)]
        session = FakeSession([], [], [])

        await load_busyness_inputs(session, gyms, at=MONDAY_NOON, now=NOW)  # type: ignore[arg-type]

        assert len(session.statements) == 3

    async def test_makes_no_queries_for_no_gyms(self) -> None:
        session = FakeSession()

        inputs = await load_busyness_inputs(session, [], at=MONDAY_NOON, now=NOW)  # type: ignore[arg-type]

        assert session.statements == []
        assert inputs.at == MONDAY_NOON
        assert inputs.now == NOW

    async def test_resolve_for_matches_resolve_busyness_on_that_gyms_rows(self) -> None:
        dogpatch = gym_row(id=1, slug="dogpatch", name="Dogpatch Boulders")
        mission = gym_row(id=2, slug="mission", name="Mission Cliffs")
        hours = [hours_row(1, 1, time(6), time(22)), hours_row(2, 1, time(6), time(22))]
        eleven_am = MONDAY_NOON - timedelta(hours=1)
        curves = [curve_row(1, 1, 11, 45), curve_row(2, 1, 11, 75)]
        snapshots = [
            snapshot_row(1, eleven_am, 30),
            snapshot_row(1, eleven_am + timedelta(minutes=30), 50),
            snapshot_row(2, MONDAY_NOON, 90),
        ]
        session = FakeSession(hours, curves, snapshots)

        inputs = await load_busyness_inputs(
            session,  # type: ignore[arg-type]
            [dogpatch, mission],
            at=eleven_am,
            now=NOW,
        )

        assert inputs.resolve_for(dogpatch) == resolve_busyness(
            eleven_am,
            now=NOW,
            timezone=LA,
            hours=[hours[0]],
            curve_pct=45,
            snapshots=snapshots[:2],
        )
        assert inputs.resolve_for(mission) == resolve_busyness(
            eleven_am,
            now=NOW,
            timezone=LA,
            hours=[hours[1]],
            curve_pct=75,
            snapshots=[snapshots[2]],
        )

    async def test_resolve_for_a_gym_with_no_rows_is_closed(self) -> None:
        session = FakeSession([], [], [])
        gym = gym_row()

        inputs = await load_busyness_inputs(session, [gym], at=MONDAY_NOON, now=NOW)  # type: ignore[arg-type]

        assert inputs.resolve_for(gym) == ResolvedBusyness(at=MONDAY_NOON, is_open=False)
