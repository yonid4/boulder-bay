from datetime import UTC, datetime, time

from app.db import models as db
from app.services.busyness import local_slot, resolve_is_open

LA = "America/Los_Angeles"


def hours_row(gym_id: int, day: int, opens: time, closes: time) -> db.GymHours:
    return db.GymHours(gym_id=gym_id, day_of_week=day, opens_at=opens, closes_at=closes)


# Sunday 2026-09-13 through Saturday 2026-09-19, 06:00-22:00 local.
WEEK = [hours_row(1, day, time(6), time(22)) for day in range(7)]


class TestLocalSlot:
    def test_takes_day_and_hour_in_the_gym_timezone(self) -> None:
        # 2026-09-14T03:30Z is Sunday 20:30 PDT.
        assert local_slot(datetime(2026, 9, 14, 3, 30, tzinfo=UTC), LA) == (0, 20)

    def test_saturday_is_day_six(self) -> None:
        # Saturday 2026-09-19 23:59 PDT.
        assert local_slot(datetime(2026, 9, 20, 6, 59, tzinfo=UTC), LA) == (6, 23)


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
