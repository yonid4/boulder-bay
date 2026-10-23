from datetime import UTC, date, datetime, time, timedelta

import pytest

from app.api.models import BusynessLevel, BusynessSource
from app.db import models as db
from app.services.busyness import (
    best_time,
    forecast_points,
    is_live,
    level_for,
    local_day,
    local_hour,
    local_slot,
    observed_pct,
    open_during,
    resolve_busyness,
    resolve_is_open,
    resolve_open_busyness,
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


FRIDAY = 5
FRIDAY_HOURS = [hours_row(1, FRIDAY, time(7), time(22)), hours_row(1, 0, time(10), time(19))]


class TestOpenDuring:
    def test_hour_inside_opening_hours(self) -> None:
        assert open_during(FRIDAY_HOURS, FRIDAY, 12) is True

    def test_opening_and_closing_hours(self) -> None:
        assert open_during(FRIDAY_HOURS, FRIDAY, 7) is True
        assert open_during(FRIDAY_HOURS, FRIDAY, 6) is False
        assert open_during(FRIDAY_HOURS, FRIDAY, 21) is True
        assert open_during(FRIDAY_HOURS, FRIDAY, 22) is False

    def test_partial_hour_counts_as_open(self) -> None:
        half = [hours_row(1, FRIDAY, time(6, 30), time(22, 30))]
        assert open_during(half, FRIDAY, 6) is True
        assert open_during(half, FRIDAY, 22) is True
        assert open_during(half, FRIDAY, 23) is False

    def test_day_without_hours_is_closed(self) -> None:
        assert open_during(FRIDAY_HOURS, 3, 12) is False


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


# 13:00-14:00 PDT on AT's day: an hour that is over by NOW.
PAST_HOUR = AT - timedelta(hours=1)


def observed(live_pct: int | None, at: datetime) -> db.BusynessSnapshot:
    return db.BusynessSnapshot(gym_id=1, observed_at=at, live_pct=live_pct)


class TestLocalHour:
    def test_bounds_are_the_local_hour_in_utc(self) -> None:
        assert local_hour(AT + timedelta(minutes=37), LA) == (AT, AT + timedelta(hours=1))

    def test_top_of_the_hour_starts_its_own_hour(self) -> None:
        assert local_hour(AT, LA)[0] == AT


class TestObservedPct:
    def test_averages_the_readings_in_a_finished_hour(self) -> None:
        rows = [observed(40, PAST_HOUR), observed(61, PAST_HOUR + timedelta(minutes=30))]
        assert observed_pct(PAST_HOUR, NOW, LA, rows) == 50

    def test_single_reading_is_used_as_is(self) -> None:
        assert observed_pct(PAST_HOUR, NOW, LA, [observed(73, PAST_HOUR)]) == 73

    def test_skips_snapshots_without_a_live_reading(self) -> None:
        rows = [observed(None, PAST_HOUR), observed(30, PAST_HOUR + timedelta(minutes=30))]
        assert observed_pct(PAST_HOUR, NOW, LA, rows) == 30
        assert observed_pct(PAST_HOUR, NOW, LA, [observed(None, PAST_HOUR)]) is None

    def test_ignores_snapshots_outside_the_hour(self) -> None:
        rows = [
            observed(90, PAST_HOUR - timedelta(seconds=1)),
            observed(20, PAST_HOUR),
            observed(90, AT),
        ]
        assert observed_pct(PAST_HOUR, NOW, LA, rows) == 20

    def test_hour_in_progress_has_no_observed_value(self) -> None:
        assert observed_pct(AT, NOW, LA, [observed(20, AT)]) is None

    def test_an_earlier_day_counts(self) -> None:
        yesterday = PAST_HOUR - timedelta(days=1)
        assert observed_pct(yesterday, NOW, LA, [observed(55, yesterday)]) == 55

    def test_hour_counts_from_the_moment_it_ends(self) -> None:
        rows = [observed(20, PAST_HOUR)]
        assert observed_pct(PAST_HOUR, AT, LA, rows) == 20
        assert observed_pct(PAST_HOUR, AT - timedelta(seconds=1), LA, rows) is None


def snapshot(live_pct: int | None, minutes_old: int = 10) -> db.BusynessSnapshot:
    return db.BusynessSnapshot(
        gym_id=1, observed_at=NOW - timedelta(minutes=minutes_old), live_pct=live_pct
    )


class TestResolveBusyness:
    def test_closed_gym_has_no_value_even_with_data(self) -> None:
        closed = [hours_row(1, 1, time(6), time(12))]

        result = resolve_busyness(
            AT, now=NOW, timezone=LA, hours=closed, curve_pct=50, snapshots=[snapshot(80)]
        )

        assert result.is_open is False
        assert (result.busy_pct, result.level, result.source) == (None, None, None)

    def test_fresh_snapshot_wins_over_the_curve(self) -> None:
        result = resolve_busyness(
            AT, now=NOW, timezone=LA, hours=WEEK, curve_pct=50, snapshots=[snapshot(80)]
        )

        assert result.is_open is True
        assert (result.busy_pct, result.level, result.source) == (
            80,
            BusynessLevel.PACKED,
            BusynessSource.LIVE,
        )

    def test_stale_snapshot_falls_back_to_the_curve(self) -> None:
        result = resolve_busyness(
            AT, now=NOW, timezone=LA, hours=WEEK, curve_pct=50, snapshots=[snapshot(80, 45)]
        )

        assert (result.busy_pct, result.level, result.source) == (
            50,
            BusynessLevel.MODERATE,
            BusynessSource.FORECAST,
        )

    def test_snapshot_without_a_live_reading_falls_back_to_the_curve(self) -> None:
        result = resolve_busyness(
            AT, now=NOW, timezone=LA, hours=WEEK, curve_pct=50, snapshots=[snapshot(None)]
        )

        assert result.source is BusynessSource.FORECAST

    def test_finished_hour_uses_its_observed_mean_over_the_curve(self) -> None:
        rows = [observed(60, PAST_HOUR), observed(80, PAST_HOUR + timedelta(minutes=30))]

        result = resolve_busyness(
            PAST_HOUR, now=NOW, timezone=LA, hours=WEEK, curve_pct=20, snapshots=rows
        )

        assert (result.busy_pct, result.level, result.source) == (
            70,
            BusynessLevel.PACKED,
            BusynessSource.OBSERVED,
        )

    def test_finished_hour_without_readings_falls_back_to_the_curve(self) -> None:
        result = resolve_busyness(
            PAST_HOUR,
            now=NOW,
            timezone=LA,
            hours=WEEK,
            curve_pct=20,
            snapshots=[observed(None, PAST_HOUR), snapshot(80)],
        )

        assert (result.busy_pct, result.source) == (20, BusynessSource.FORECAST)

    def test_current_hour_stays_live_alongside_older_snapshots(self) -> None:
        rows = [observed(10, AT - timedelta(hours=1)), snapshot(80), observed(15, AT)]

        result = resolve_busyness(
            AT, now=NOW, timezone=LA, hours=WEEK, curve_pct=50, snapshots=rows
        )

        assert (result.busy_pct, result.source) == (80, BusynessSource.LIVE)

    def test_open_without_data_is_no_forecast_not_zero(self) -> None:
        result = resolve_busyness(
            AT, now=NOW, timezone=LA, hours=WEEK, curve_pct=None, snapshots=[]
        )

        assert result.is_open is True
        assert (result.busy_pct, result.level, result.source) == (None, None, None)

    def test_curve_zero_is_a_real_forecast(self) -> None:
        result = resolve_busyness(AT, now=NOW, timezone=LA, hours=WEEK, curve_pct=0, snapshots=[])

        assert (result.busy_pct, result.level) == (0, BusynessLevel.QUIET)


def pdt(hour: int, minute: int = 0) -> datetime:
    """Monday 2026-09-14 at `hour:minute` PDT, as UTC."""

    return datetime(2026, 9, 14, 7, minute, tzinfo=UTC) + timedelta(hours=hour)


# Monday 06:00-22:00. Curve rows are keyed by local hour for Monday.
MONDAY_CURVE = {hour: 50 for hour in range(6, 22)}


class TestBestTime:
    @pytest.mark.parametrize(
        ("at", "curve", "expected_hour"),
        [
            pytest.param(pdt(9), {**MONDAY_CURVE, 15: 20}, 15, id="lowest-curve-hour"),
            pytest.param(pdt(9), {**MONDAY_CURVE, 11: 20, 18: 20}, 11, id="tie-goes-earliest"),
            pytest.param(pdt(9), {**MONDAY_CURVE, 7: 5, 10: 30}, 10, id="past-hour-ignored"),
            pytest.param(pdt(9), {**MONDAY_CURVE, 9: 5, 10: 30}, 10, id="current-hour-ignored"),
            pytest.param(
                pdt(9, 45), {**MONDAY_CURVE, 9: 5, 10: 30}, 10, id="minutes-do-not-change-hour"
            ),
            pytest.param(pdt(9), {**MONDAY_CURVE, 12: 0}, 12, id="zero-is-a-real-forecast"),
            pytest.param(pdt(9), {11: 60, 14: 40}, 14, id="hours-without-curve-skipped"),
            pytest.param(pdt(9), {**MONDAY_CURVE, 22: 1, 23: 1}, 10, id="closed-hours-skipped"),
            pytest.param(pdt(20), {**MONDAY_CURVE, 21: 70}, 21, id="last-open-hour"),
            pytest.param(pdt(21), MONDAY_CURVE, None, id="closes-soon"),
            pytest.param(pdt(9), {}, None, id="no-forecast-left"),
            pytest.param(pdt(2), {**MONDAY_CURVE, 6: 10}, 6, id="before-opening-includes-first"),
        ],
    )
    def test_table(self, at: datetime, curve: dict[int, int], expected_hour: int | None) -> None:
        result = best_time(at, timezone=LA, hours=WEEK, curve=curve)

        assert (None if result is None else result.starts_at) == (
            None if expected_hour is None else pdt(expected_hour)
        )

    def test_point_is_a_forecast_hour(self) -> None:
        result = best_time(pdt(9), timezone=LA, hours=WEEK, curve={**MONDAY_CURVE, 15: 20})

        assert result is not None
        assert (result.starts_at, result.ends_at) == (pdt(15), pdt(16))
        assert (result.busy_pct, result.level, result.source) == (
            20,
            BusynessLevel.QUIET,
            BusynessSource.FORECAST,
        )

    def test_partially_open_hour_can_be_picked(self) -> None:
        late = [hours_row(1, 1, time(6), time(21, 30))]

        result = best_time(pdt(9), timezone=LA, hours=late, curve={**MONDAY_CURVE, 21: 5})

        assert result is not None
        assert result.starts_at == pdt(21)

    def test_day_is_the_local_day_of_at(self) -> None:
        # 2026-09-15T03:30Z is still Monday 20:30 PDT; the rest of Monday is hour 21.
        at = datetime(2026, 9, 15, 3, 30, tzinfo=UTC)

        result = best_time(at, timezone=LA, hours=WEEK, curve={21: 40})

        assert result is not None
        assert result.starts_at == pdt(21)

    def test_closed_day_has_no_best_time(self) -> None:
        no_monday = [row for row in WEEK if row.day_of_week != 1]

        assert best_time(pdt(9), timezone=LA, hours=no_monday, curve=MONDAY_CURVE) is None


class TestLocalDay:
    def test_bounds_are_local_midnights_in_utc(self) -> None:
        assert local_day(pdt(9), LA) == (date(2026, 9, 14), pdt(0), pdt(24))

    def test_takes_the_date_in_the_gym_timezone(self) -> None:
        # 2026-09-15T03:30Z is still Monday 20:30 PDT.
        assert local_day(datetime(2026, 9, 15, 3, 30, tzinfo=UTC), LA)[0] == date(2026, 9, 14)

    def test_spring_forward_day_is_23_hours(self) -> None:
        # Sunday 2026-03-08: midnight is PST (-8), the next midnight PDT (-7).
        day, start, end = local_day(datetime(2026, 3, 8, 20, tzinfo=UTC), LA)
        assert day == date(2026, 3, 8)
        assert start == datetime(2026, 3, 8, 8, tzinfo=UTC)
        assert end - start == timedelta(hours=23)

    def test_fall_back_day_is_25_hours(self) -> None:
        # Sunday 2026-11-01: midnight is PDT (-7), the next midnight PST (-8).
        day, start, end = local_day(datetime(2026, 11, 1, 20, tzinfo=UTC), LA)
        assert day == date(2026, 11, 1)
        assert start == datetime(2026, 11, 1, 7, tzinfo=UTC)
        assert end - start == timedelta(hours=25)


class TestResolveOpenBusyness:
    def test_matches_resolve_busyness_for_an_open_gym(self) -> None:
        cases = [
            (AT, [snapshot(20)], 45),
            (PAST_HOUR, [observed(40, PAST_HOUR)], 45),
            (AT + timedelta(hours=2), [snapshot(20)], 45),
            (AT + timedelta(hours=2), [], None),
        ]
        for at, rows, curve_pct in cases:
            assert resolve_open_busyness(
                at, now=NOW, timezone=LA, curve_pct=curve_pct, snapshots=rows
            ) == resolve_busyness(
                at, now=NOW, timezone=LA, hours=WEEK, curve_pct=curve_pct, snapshots=rows
            )

    def test_skips_the_opening_hours_check(self) -> None:
        result = resolve_open_busyness(pdt(3), now=NOW, timezone=LA, curve_pct=10, snapshots=[])

        assert (result.is_open, result.busy_pct) == (True, 10)


# Monday's opening hours for the forecast tests; the wall clock reads 14:50 PDT (NOW).
MONDAY_ONLY = [hours_row(1, 1, time(6, 30), time(21, 30))]


class TestForecastPoints:
    def test_one_point_per_hour_the_gym_is_open_at_all(self) -> None:
        points = forecast_points(
            pdt(9), now=NOW, timezone=LA, hours=MONDAY_ONLY, curve={}, snapshots=[]
        )

        assert [point.starts_at for point in points] == [pdt(hour) for hour in range(6, 22)]
        assert all(point.ends_at - point.starts_at == timedelta(hours=1) for point in points)

    def test_a_closed_day_has_no_points(self) -> None:
        sunday = datetime(2026, 9, 13, 19, tzinfo=UTC)

        assert (
            forecast_points(
                sunday, now=NOW, timezone=LA, hours=MONDAY_ONLY, curve={6: 10}, snapshots=[]
            )
            == []
        )

    @pytest.mark.parametrize(
        ("hour", "snapshots", "curve", "expected"),
        [
            pytest.param(
                11,
                [observed(30, pdt(11)), observed(51, pdt(11, 30))],
                {11: 80},
                (BusynessSource.OBSERVED, 40),
                id="past-observed-beats-curve",
            ),
            pytest.param(
                11, [], {11: 80}, (BusynessSource.FORECAST, 80), id="past-without-snapshots-curve"
            ),
            pytest.param(
                11,
                [observed(None, pdt(11))],
                {11: 80},
                (BusynessSource.FORECAST, 80),
                id="past-null-readings-curve",
            ),
            pytest.param(11, [], {}, (None, None), id="past-gap"),
            pytest.param(
                14, [snapshot(25)], {14: 80}, (BusynessSource.LIVE, 25), id="current-live"
            ),
            pytest.param(
                14,
                [snapshot(25, minutes_old=45)],
                {14: 80},
                (BusynessSource.FORECAST, 80),
                id="current-stale-curve",
            ),
            pytest.param(
                14,
                [observed(25, pdt(14))],
                {},
                (None, None),
                id="current-never-observed",
            ),
            pytest.param(
                18, [snapshot(25)], {18: 0}, (BusynessSource.FORECAST, 0), id="future-curve-zero"
            ),
            pytest.param(18, [snapshot(25)], {}, (None, None), id="future-gap-not-zero"),
        ],
    )
    def test_source_table(
        self,
        hour: int,
        snapshots: list[db.BusynessSnapshot],
        curve: dict[int, int],
        expected: tuple[BusynessSource | None, int | None],
    ) -> None:
        points = forecast_points(
            pdt(9), now=NOW, timezone=LA, hours=MONDAY_ONLY, curve=curve, snapshots=snapshots
        )

        point = next(point for point in points if point.starts_at == pdt(hour))
        assert (point.source, point.busy_pct) == expected
        assert point.level == (None if expected[1] is None else level_for(expected[1]))

    def test_each_point_agrees_with_resolve_busyness_inside_its_hour(self) -> None:
        curve = {hour: hour * 3 for hour in range(6, 22) if hour != 17}
        rows = [observed(33, pdt(10, 30)), snapshot(25)]

        points = forecast_points(
            pdt(9), now=NOW, timezone=LA, hours=WEEK, curve=curve, snapshots=rows
        )

        for point in points:
            inside = point.starts_at + timedelta(minutes=45)
            resolved = resolve_busyness(
                inside,
                now=NOW,
                timezone=LA,
                hours=WEEK,
                curve_pct=curve.get(local_slot(inside, LA)[1]),
                snapshots=rows,
            )
            assert (point.busy_pct, point.level, point.source) == (
                resolved.busy_pct,
                resolved.level,
                resolved.source,
            )

    def test_another_days_hours_are_relative_to_now(self) -> None:
        tomorrow = [hours_row(1, 2, time(6), time(22))]
        tuesday_9am = pdt(9) + timedelta(days=1)

        points = forecast_points(
            tuesday_9am,
            now=NOW,
            timezone=LA,
            hours=tomorrow,
            curve={14: 60},
            snapshots=[snapshot(25)],
        )

        two_pm = next(point for point in points if point.starts_at == pdt(14) + timedelta(days=1))
        assert (two_pm.source, two_pm.busy_pct) == (BusynessSource.FORECAST, 60)

    def test_spring_forward_day_has_no_missing_or_doubled_hours(self) -> None:
        all_sunday = [hours_row(1, 0, time(0), time(23, 59))]
        at = datetime(2026, 3, 8, 20, tzinfo=UTC)

        points = forecast_points(
            at, now=NOW, timezone=LA, hours=all_sunday, curve={1: 10, 3: 30}, snapshots=[]
        )

        assert len(points) == 23
        starts = [point.starts_at for point in points]
        assert starts == [
            datetime(2026, 3, 8, 8, tzinfo=UTC) + timedelta(hours=h) for h in range(23)
        ]
        assert [point.busy_pct for point in points[1:3]] == [10, 30]

    def test_fall_back_day_repeats_the_one_oclock_hour(self) -> None:
        all_sunday = [hours_row(1, 0, time(0), time(23, 59))]
        at = datetime(2026, 11, 1, 20, tzinfo=UTC)

        points = forecast_points(
            at, now=NOW, timezone=LA, hours=all_sunday, curve={1: 10, 2: 20}, snapshots=[]
        )

        assert len(points) == 25
        assert [point.busy_pct for point in points[1:4]] == [10, 10, 20]
        assert len({point.starts_at for point in points}) == 25
