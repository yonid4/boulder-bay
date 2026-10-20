from collections.abc import Sequence
from datetime import UTC, datetime, time
from typing import Any

import pytest

from app.api.models import GymBrand
from app.db import models as db
from app.services.gyms import list_gyms, resolve_is_open, to_api_gym

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

        return Result()


class TestResolveIsOpen:
    def test_inside_hours_is_open(self) -> None:
        # Monday 2026-09-14 12:00 PDT = 19:00Z
        at = datetime(2026, 9, 14, 19, tzinfo=UTC)
        assert resolve_is_open(at, LA, WEEK) is True

    def test_before_opening_is_closed(self) -> None:
        # Monday 05:59 PDT
        at = datetime(2026, 9, 14, 12, 59, tzinfo=UTC)
        assert resolve_is_open(at, LA, WEEK) is False

    def test_opening_minute_is_open_and_closing_minute_is_closed(self) -> None:
        opens = datetime(2026, 9, 14, 13, tzinfo=UTC)  # 06:00 PDT
        closes = datetime(2026, 9, 15, 5, tzinfo=UTC)  # 22:00 PDT
        assert resolve_is_open(opens, LA, WEEK) is True
        assert resolve_is_open(closes, LA, WEEK) is False

    def test_no_row_for_the_day_is_closed(self) -> None:
        weekdays_only = [row for row in WEEK if row.day_of_week not in (0, 6)]
        sunday_noon = datetime(2026, 9, 13, 19, tzinfo=UTC)
        assert resolve_is_open(sunday_noon, LA, weekdays_only) is False
        monday_noon = datetime(2026, 9, 14, 19, tzinfo=UTC)
        assert resolve_is_open(monday_noon, LA, weekdays_only) is True

    def test_day_is_resolved_in_the_gym_timezone_not_utc(self) -> None:
        # 2026-09-14T03:30Z is still Sunday 20:30 PDT. A gym closed on Sundays but open
        # Monday nights must report closed here.
        sunday_closed = [row for row in WEEK if row.day_of_week != 0]
        at = datetime(2026, 9, 14, 3, 30, tzinfo=UTC)
        assert resolve_is_open(at, LA, sunday_closed) is False


class TestToApiGym:
    def test_maps_columns_and_leaves_busyness_empty(self) -> None:
        at = datetime(2026, 9, 14, 19, tzinfo=UTC)

        gym = to_api_gym(gym_row(), at=at, hours=WEEK)

        assert gym.slug == "dogpatch"
        assert gym.name == "Dogpatch Boulders"
        assert gym.brand is GymBrand.TOUCHSTONE
        assert gym.city == "San Francisco"
        assert gym.latitude == 37.7567
        assert gym.longitude == -122.3903
        assert gym.logo_url is None
        assert gym.busyness.at == at
        assert gym.busyness.is_open is True
        assert gym.busyness.busy_pct is None
        assert gym.busyness.level is None
        assert gym.busyness.source is None


class TestListGyms:
    async def test_groups_hours_by_gym_and_preserves_query_order(self) -> None:
        gyms = [
            gym_row(id=1, slug="dogpatch", name="Dogpatch Boulders"),
            gym_row(id=2, slug="mosaic", name="Mosaic Boulders", brand="independent"),
        ]
        hours = [
            hours_row(1, 1, time(6), time(22)),
            hours_row(2, 1, time(10), time(12)),
        ]
        session = FakeSession(gyms, hours)
        at = datetime(2026, 9, 14, 19, tzinfo=UTC)  # Monday 12:00 PDT

        result = await list_gyms(session, at=at)  # type: ignore[arg-type]

        assert [gym.slug for gym in result] == ["dogpatch", "mosaic"]
        assert result[0].busyness.is_open is True
        assert result[1].busyness.is_open is False
        assert result[1].brand is GymBrand.INDEPENDENT
        assert len(session.statements) == 2

    async def test_defaults_at_to_now_in_utc(self) -> None:
        before = datetime.now(UTC)
        session = FakeSession([gym_row()], WEEK)

        result = await list_gyms(session)  # type: ignore[arg-type]

        assert result[0].busyness.at.tzinfo is not None
        assert before <= result[0].busyness.at <= datetime.now(UTC)

    async def test_rejects_naive_at(self) -> None:
        session = FakeSession([gym_row()], WEEK)

        with pytest.raises(ValueError, match="timezone"):
            await list_gyms(session, at=datetime(2026, 9, 14, 12))  # type: ignore[arg-type]
        assert session.statements == []

    async def test_skips_hours_query_when_there_are_no_gyms(self) -> None:
        session = FakeSession([])

        assert await list_gyms(session, at=datetime(2026, 9, 14, tzinfo=UTC)) == []  # type: ignore[arg-type]
        assert len(session.statements) == 1
