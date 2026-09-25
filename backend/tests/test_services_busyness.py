from datetime import UTC, datetime, time, timedelta

import pytest

from app.api.models import BusynessLevel, BusynessSource
from app.db import models as db
from app.services.busyness import (
    is_live,
    level_for,
    local_slot,
    resolve_busyness,
    resolve_is_open,
)

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


class TestLevelFor:
    @pytest.mark.parametrize(
        ("pct", "level"),
        [
            (0, BusynessLevel.QUIET),
            (39, BusynessLevel.QUIET),
            (40, BusynessLevel.MODERATE),
            (69, BusynessLevel.MODERATE),
            (70, BusynessLevel.PACKED),
            (100, BusynessLevel.PACKED),
        ],
    )
    def test_thresholds(self, pct: int, level: BusynessLevel) -> None:
        assert level_for(pct) is level


# Monday 2026-09-14: the app asks for 14:00 PDT; the wall clock reads 14:50 PDT.
AT = datetime(2026, 9, 14, 21, tzinfo=UTC)
NOW = datetime(2026, 9, 14, 21, 50, tzinfo=UTC)


class TestIsLive:
    def test_fresh_snapshot_in_the_current_hour_is_live(self) -> None:
        assert is_live(AT, NOW, LA, NOW - timedelta(minutes=10)) is True

    def test_snapshot_from_the_previous_hour_still_counts_within_45_minutes(self) -> None:
        now = datetime(2026, 9, 14, 21, 10, tzinfo=UTC)  # 14:10, snapshot at 13:50
        assert is_live(AT, now, LA, now - timedelta(minutes=20)) is True

    def test_exactly_45_minutes_old_is_not_live(self) -> None:
        assert is_live(AT, NOW, LA, NOW - timedelta(minutes=45)) is False
        assert is_live(AT, NOW, LA, NOW - timedelta(minutes=44, seconds=59)) is True

    def test_snapshot_from_the_future_is_not_live(self) -> None:
        assert is_live(AT, NOW, LA, NOW + timedelta(seconds=1)) is False

    def test_another_hour_is_never_live(self) -> None:
        observed = NOW - timedelta(minutes=5)
        assert is_live(AT - timedelta(hours=1), NOW, LA, observed) is False
        assert is_live(AT + timedelta(hours=1), NOW, LA, observed) is False

    def test_same_hour_on_another_day_is_not_live(self) -> None:
        assert is_live(AT - timedelta(days=1), NOW, LA, NOW - timedelta(minutes=5)) is False


def snapshot(live_pct: int | None, minutes_old: int = 10) -> db.BusynessSnapshot:
    return db.BusynessSnapshot(
        gym_id=1, observed_at=NOW - timedelta(minutes=minutes_old), live_pct=live_pct
    )


class TestResolveBusyness:
    def test_closed_gym_has_no_value_even_with_data(self) -> None:
        closed = [hours_row(1, 1, time(6), time(12))]

        result = resolve_busyness(
            AT, now=NOW, timezone=LA, hours=closed, curve_pct=50, snapshot=snapshot(80)
        )

        assert result.is_open is False
        assert (result.busy_pct, result.level, result.source) == (None, None, None)

    def test_fresh_snapshot_wins_over_the_curve(self) -> None:
        result = resolve_busyness(
            AT, now=NOW, timezone=LA, hours=WEEK, curve_pct=50, snapshot=snapshot(80)
        )

        assert result.is_open is True
        assert (result.busy_pct, result.level, result.source) == (
            80,
            BusynessLevel.PACKED,
            BusynessSource.LIVE,
        )

    def test_stale_snapshot_falls_back_to_the_curve(self) -> None:
        result = resolve_busyness(
            AT, now=NOW, timezone=LA, hours=WEEK, curve_pct=50, snapshot=snapshot(80, 45)
        )

        assert (result.busy_pct, result.level, result.source) == (
            50,
            BusynessLevel.MODERATE,
            BusynessSource.FORECAST,
        )

    def test_snapshot_without_a_live_reading_falls_back_to_the_curve(self) -> None:
        result = resolve_busyness(
            AT, now=NOW, timezone=LA, hours=WEEK, curve_pct=50, snapshot=snapshot(None)
        )

        assert result.source is BusynessSource.FORECAST

    def test_open_without_data_is_no_forecast_not_zero(self) -> None:
        result = resolve_busyness(
            AT, now=NOW, timezone=LA, hours=WEEK, curve_pct=None, snapshot=None
        )

        assert result.is_open is True
        assert (result.busy_pct, result.level, result.source) == (None, None, None)

    def test_curve_zero_is_a_real_forecast(self) -> None:
        result = resolve_busyness(AT, now=NOW, timezone=LA, hours=WEEK, curve_pct=0, snapshot=None)

        assert (result.busy_pct, result.level) == (0, BusynessLevel.QUIET)
