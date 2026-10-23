from collections.abc import Sequence
from datetime import UTC, date, datetime, time, timedelta
from typing import Any

import pytest
from sqlalchemy.dialects import postgresql

from app.api.models import BusynessLevel, BusynessSource, GymBrand, ResolvedBusyness
from app.db import models as db
from app.services.busyness import best_time, resolve_busyness
from app.services.gyms import (
    GymLogoImage,
    get_gym_detail,
    get_gym_logo,
    list_gyms,
    load_busyness_inputs,
    to_api_gym,
)

LA = "America/Los_Angeles"


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

            def first(self) -> Any:
                return rows[0] if rows else None

        return Result()


class TestToApiGym:
    def test_maps_columns_and_passes_busyness_through(self) -> None:
        at = datetime(2026, 9, 14, 19, tzinfo=UTC)
        busyness = ResolvedBusyness(at=at, is_open=True, busy_pct=35, level=BusynessLevel.QUIET)

        gym = to_api_gym(gym_row(), busyness=busyness)

        assert gym.slug == "dogpatch"
        assert gym.name == "Dogpatch Boulders"
        assert gym.brand is GymBrand.TOUCHSTONE
        assert gym.city == "San Francisco"
        assert gym.latitude == 37.7567
        assert gym.longitude == -122.3903
        assert gym.logo_url is None
        assert gym.busyness == busyness

    def test_fills_logo_url_when_the_gym_has_a_logo(self) -> None:
        at = datetime(2026, 9, 14, 19, tzinfo=UTC)

        gym = to_api_gym(
            gym_row(),
            busyness=ResolvedBusyness(at=at, is_open=True),
            logo_url_for=lambda slug: f"http://testserver/api/gyms/{slug}/logo",
        )

        assert str(gym.logo_url) == "http://testserver/api/gyms/dogpatch/logo"

    def test_leaves_logo_url_empty_when_the_gym_has_no_logo(self) -> None:
        at = datetime(2026, 9, 14, 19, tzinfo=UTC)

        gym = to_api_gym(
            gym_row(logo_id=None),
            busyness=ResolvedBusyness(at=at, is_open=True),
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
        session = FakeSession(gyms, hours, curves, snapshots)

        result = await list_gyms(session, at=MONDAY_NOON, now=NOW)  # type: ignore[arg-type]

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
        assert len(session.statements) == 4

    async def test_filters_curves_to_each_gyms_local_hour(self) -> None:
        session = FakeSession([gym_row()], WEEK, [], [])

        await list_gyms(session, at=MONDAY_NOON, now=NOW)  # type: ignore[arg-type]

        curve_sql = str(session.statements[2].compile(dialect=postgresql.dialect()))
        columns = "busyness_curves.gym_id, busyness_curves.day_of_week, busyness_curves.hour_of_day"
        assert f"({columns}) IN" in curve_sql
        params = session.statements[2].compile(dialect=postgresql.dialect()).params
        assert (1, 1, 12) in next(iter(params.values()))

    async def test_fetches_snapshots_in_the_live_window_or_the_requested_hour(self) -> None:
        session = FakeSession([gym_row()], WEEK, [], [])
        at = MONDAY_NOON - timedelta(hours=2, minutes=-15)  # 10:15 PDT, an hour that is over

        await list_gyms(session, at=at, now=NOW)  # type: ignore[arg-type]

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
        session = FakeSession(gyms, hours, curves, snapshots)

        result = await list_gyms(session, at=eleven_am, now=NOW)  # type: ignore[arg-type]

        dogpatch, mission = (gym.busyness for gym in result)
        assert (dogpatch.source, dogpatch.busy_pct) == (BusynessSource.OBSERVED, 40)
        assert (mission.source, mission.busy_pct) == (BusynessSource.FORECAST, 75)

    async def test_defaults_at_to_now_in_utc(self) -> None:
        before = datetime.now(UTC)
        session = FakeSession([gym_row()], WEEK, [], [])

        result = await list_gyms(session)  # type: ignore[arg-type]

        assert result[0].busyness.at.tzinfo is not None
        assert before <= result[0].busyness.at <= datetime.now(UTC)

    async def test_rejects_naive_at(self) -> None:
        session = FakeSession([gym_row()], WEEK)

        with pytest.raises(ValueError, match="timezone"):
            await list_gyms(session, at=datetime(2026, 9, 14, 12))  # type: ignore[arg-type]
        assert session.statements == []

    async def test_skips_the_other_queries_when_there_are_no_gyms(self) -> None:
        session = FakeSession([])

        assert await list_gyms(session, at=datetime(2026, 9, 14, tzinfo=UTC)) == []  # type: ignore[arg-type]
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


def detail_gym_row() -> db.Gym:
    return gym_row(
        address="2573 3rd St, San Francisco, CA 94107",
        website_url="https://touchstoneclimbing.com/dogpatch-boulders/",
        waiver_url="https://example.com/waiver",
        day_pass_cents=3000,
        day_pass_peak_cents=3500,
        peak_starts_at=time(15),
        monthly_cents=12000,
    )


# Monday's curve, 06:00-22:00 local: 50% except 45% at noon and 20% at 16:00.
MONDAY_CURVE_ROWS = [curve_row(1, 1, hour, 50) for hour in range(6, 22) if hour not in (12, 16)]
MONDAY_CURVE_ROWS += [curve_row(1, 1, 12, 45), curve_row(1, 1, 16, 20)]
ELEVEN_AM = MONDAY_NOON - timedelta(hours=1)
DAY_SNAPSHOTS = [
    snapshot_row(1, ELEVEN_AM, 30),
    snapshot_row(1, ELEVEN_AM + timedelta(minutes=30), 50),
    snapshot_row(1, MONDAY_NOON, 20),
]


def detail_session(*, gym: db.Gym | None = None) -> FakeSession:
    """Gym, then the three `load_busyness_inputs` queries, then the day's curve and
    snapshots."""

    return FakeSession(
        [gym or detail_gym_row()],
        WEEK,
        [curve_row(1, 1, 12, 45)],
        [DAY_SNAPSHOTS[2]],
        MONDAY_CURVE_ROWS,
        DAY_SNAPSHOTS,
    )


def compiled(statement: Any) -> Any:
    return statement.compile(dialect=postgresql.dialect())


class TestGetGymDetail:
    async def test_returns_none_for_an_unknown_or_inactive_slug_after_one_query(self) -> None:
        session = FakeSession([])

        result = await get_gym_detail(session, "nope", at=MONDAY_NOON, now=NOW)  # type: ignore[arg-type]

        assert result is None
        assert len(session.statements) == 1
        sql = str(compiled(session.statements[0]))
        assert "gyms.slug = " in sql
        assert "gyms.is_active" in sql

    async def test_rejects_naive_at_before_querying(self) -> None:
        session = detail_session()

        with pytest.raises(ValueError, match="timezone"):
            await get_gym_detail(session, "dogpatch", at=datetime(2026, 9, 14, 12))  # type: ignore[arg-type]
        assert session.statements == []

    async def test_maps_the_gym_hours_rates_and_links(self) -> None:
        unordered = list(reversed(WEEK))
        session = FakeSession(
            [detail_gym_row()], unordered, [], [], MONDAY_CURVE_ROWS, DAY_SNAPSHOTS
        )

        detail = await get_gym_detail(
            session,  # type: ignore[arg-type]
            "dogpatch",
            at=MONDAY_NOON,
            now=NOW,
            logo_url_for=lambda slug: f"http://testserver/api/gyms/{slug}/logo",
        )

        assert detail is not None
        assert detail.gym.slug == "dogpatch"
        assert str(detail.gym.logo_url) == "http://testserver/api/gyms/dogpatch/logo"
        assert detail.address == "2573 3rd St, San Francisco, CA 94107"
        assert detail.timezone == LA
        assert str(detail.website_url) == "https://touchstoneclimbing.com/dogpatch-boulders/"
        assert str(detail.waiver_url) == "https://example.com/waiver"
        assert [row.day_of_week for row in detail.hours] == list(range(7))
        assert (detail.hours[1].opens_at, detail.hours[1].closes_at) == (time(6), time(22))
        assert (
            detail.rates.day_pass_cents,
            detail.rates.day_pass_peak_cents,
            detail.rates.peak_starts_at,
            detail.rates.monthly_cents,
        ) == (3000, 3500, time(15), 12000)

    async def test_leaves_missing_links_and_rates_empty(self) -> None:
        session = FakeSession([gym_row(logo_id=None)], WEEK, [], [], [], [])

        detail = await get_gym_detail(
            session,  # type: ignore[arg-type]
            "dogpatch",
            at=MONDAY_NOON,
            now=NOW,
            logo_url_for=lambda slug: f"http://testserver/api/gyms/{slug}/logo",
        )

        assert detail is not None
        assert (detail.address, detail.website_url, detail.waiver_url) == (None, None, None)
        assert detail.gym.logo_url is None
        assert detail.rates.model_dump() == {
            "day_pass_cents": None,
            "day_pass_peak_cents": None,
            "peak_starts_at": None,
            "monthly_cents": None,
        }

    async def test_forecast_covers_the_local_day_with_sources_and_best_time(self) -> None:
        detail = await get_gym_detail(detail_session(), "dogpatch", at=MONDAY_NOON, now=NOW)  # type: ignore[arg-type]

        assert detail is not None
        forecast = detail.forecast
        assert (forecast.date, forecast.timezone) == (date(2026, 9, 14), LA)
        six_am = MONDAY_NOON - timedelta(hours=6)
        assert [point.starts_at for point in forecast.points] == [
            six_am + timedelta(hours=hour) for hour in range(16)
        ]
        by_start = {point.starts_at: point for point in forecast.points}
        assert (by_start[ELEVEN_AM].source, by_start[ELEVEN_AM].busy_pct) == (
            BusynessSource.OBSERVED,
            40,
        )
        assert (by_start[MONDAY_NOON].source, by_start[MONDAY_NOON].busy_pct) == (
            BusynessSource.LIVE,
            20,
        )
        later = by_start[MONDAY_NOON + timedelta(hours=4)]
        assert (later.source, later.busy_pct) == (BusynessSource.FORECAST, 20)
        assert forecast.best_time == best_time(
            MONDAY_NOON,
            timezone=LA,
            hours=WEEK,
            curve={row.hour_of_day: row.busy_pct for row in MONDAY_CURVE_ROWS},
        )
        assert forecast.best_time is not None
        assert forecast.best_time.starts_at == MONDAY_NOON + timedelta(hours=4)

    async def test_gym_busyness_agrees_with_the_list_and_the_current_point(self) -> None:
        detail = await get_gym_detail(detail_session(), "dogpatch", at=MONDAY_NOON, now=NOW)  # type: ignore[arg-type]
        listed = await list_gyms(
            FakeSession([detail_gym_row()], WEEK, [curve_row(1, 1, 12, 45)], [DAY_SNAPSHOTS[2]]),  # type: ignore[arg-type]
            at=MONDAY_NOON,
            now=NOW,
        )

        assert detail is not None
        assert detail.gym == listed[0]
        current = next(p for p in detail.forecast.points if p.starts_at == MONDAY_NOON)
        busyness = detail.gym.busyness
        assert (current.busy_pct, current.level, current.source) == (
            busyness.busy_pct,
            busyness.level,
            busyness.source,
        )

    async def test_takes_six_queries_and_bounds_the_days_rows(self) -> None:
        session = detail_session()

        await get_gym_detail(session, "dogpatch", at=MONDAY_NOON, now=NOW)  # type: ignore[arg-type]

        assert len(session.statements) == 6
        curve = compiled(session.statements[4])
        assert "busyness_curves.gym_id = " in str(curve)
        assert "busyness_curves.day_of_week = " in str(curve)
        assert {1} <= set(curve.params.values())
        snapshots = compiled(session.statements[5])
        params = list(snapshots.params.values())
        midnight = MONDAY_NOON - timedelta(hours=12)
        assert midnight in params
        assert midnight + timedelta(days=1) in params
        assert NOW - timedelta(minutes=45) in params
        assert NOW in params

    async def test_takes_the_local_day_of_at_not_the_utc_day(self) -> None:
        # 2026-09-15T03:30Z is Monday 20:30 PDT.
        evening = datetime(2026, 9, 15, 3, 30, tzinfo=UTC)
        session = FakeSession([detail_gym_row()], WEEK, [], [], [], [])

        detail = await get_gym_detail(session, "dogpatch", at=evening, now=NOW)  # type: ignore[arg-type]

        assert detail is not None
        assert detail.forecast.date == date(2026, 9, 14)
        assert 1 in compiled(session.statements[4]).params.values()

    async def test_defaults_at_to_now_in_utc(self) -> None:
        before = datetime.now(UTC)

        detail = await get_gym_detail(detail_session(), "dogpatch")  # type: ignore[arg-type]

        assert detail is not None
        assert before <= detail.gym.busyness.at <= datetime.now(UTC)
