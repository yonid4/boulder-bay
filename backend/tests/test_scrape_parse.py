import pytest

from app.scrape.parse import (
    ChartShapeError,
    NoChartData,
    RawChart,
    header_weekday,
    hour_of_day,
    parse_chart,
)

NNBSP = "\u202f"  # what the live page puts before AM/PM
FRIDAY = 5
HEADER = "Popular times\nFridays\n\ue5c5\nLIVEA little busy\n6a\n9a\n12p\n3p\n6p\n9p"
LIVE = "Currently 58% busy, usually 30% busy."


def bar(pct: int, hour: int) -> str:
    clock = hour % 12 or 12
    return f"{pct}% busy at {clock}{NNBSP}{'AM' if hour < 12 else 'PM'}."


def day(pcts: dict[int, int], *, live_at: int | None = None) -> tuple[str, ...]:
    """18 bars, 6 AM-11 PM, 0% unless given; the live label replaces one hour's bar."""

    return tuple(LIVE if hour == live_at else bar(pcts.get(hour, 0), hour) for hour in range(6, 24))


def week(*, live_at: int | None = 9) -> tuple[tuple[str, ...], ...]:
    # Shaped like Dogpatch Boulders on Friday 2026-09-25 at 9:50 AM.
    return tuple(
        day({10: 30 + d, 18: 70 + d}, live_at=live_at if d == FRIDAY else None) for d in range(7)
    )


def chart(**overrides: object) -> RawChart:
    values: dict[str, object] = {
        "place_name": "Dogpatch Boulders",
        "header": HEADER,
        "days": week(),
    }
    values.update(overrides)
    return RawChart(**values)  # type: ignore[arg-type]


class TestHourOfDay:
    @pytest.mark.parametrize(
        ("hour", "meridiem", "expected"),
        [
            (12, "AM", 0),
            (1, "AM", 1),
            (11, "AM", 11),
            (12, "PM", 12),
            (1, "PM", 13),
            (11, "PM", 23),
        ],
    )
    def test_twelve_hour_clock(self, hour: int, meridiem: str, expected: int) -> None:
        assert hour_of_day(hour, meridiem) == expected

    def test_rejects_hour_off_the_clock(self) -> None:
        with pytest.raises(ChartShapeError):
            hour_of_day(13, "PM")


class TestHeaderWeekday:
    def test_reads_plural_day_name(self) -> None:
        assert header_weekday(HEADER) == FRIDAY

    def test_reads_singular_day_name(self) -> None:
        assert header_weekday("Popular times\nSunday") == 0

    def test_rejects_header_without_a_day(self) -> None:
        with pytest.raises(ChartShapeError, match="one weekday"):
            header_weekday("Popular times\n6a\n9a")

    def test_rejects_header_naming_two_days(self) -> None:
        with pytest.raises(ChartShapeError, match="one weekday"):
            header_weekday("Mondays\nTuesdays")


class TestParseChart:
    def test_maps_days_sunday_first(self) -> None:
        reading = parse_chart(chart(), today=FRIDAY)

        assert reading.place_name == "Dogpatch Boulders"
        assert reading.bars[(0, 10)] == 30  # Sunday
        assert reading.bars[(6, 18)] == 76  # Saturday
        assert reading.bars[(3, 23)] == 0

    def test_keeps_zero_bars_for_the_writer_to_filter(self) -> None:
        reading = parse_chart(chart(), today=FRIDAY)

        # 7 days x 18 bars, minus Friday 9 AM which carries the live label.
        assert len(reading.bars) == 7 * 18 - 1
        assert (FRIDAY, 9) not in reading.bars
        assert reading.bars[(1, 6)] == 0

    def test_reads_the_live_label(self) -> None:
        reading = parse_chart(chart(), today=FRIDAY)

        assert reading.live_pct == 58
        assert reading.typical_pct == 30

    def test_no_live_label_leaves_live_empty(self) -> None:
        reading = parse_chart(chart(days=week(live_at=None)), today=FRIDAY)

        assert reading.live_pct is None
        assert reading.typical_pct is None
        assert len(reading.bars) == 7 * 18

    def test_accepts_a_plain_space_before_the_meridiem(self) -> None:
        days = tuple(tuple(label.replace(NNBSP, " ") for label in d) for d in week())

        assert parse_chart(chart(days=days), today=FRIDAY).bars[(0, 10)] == 30

    def test_ignores_labels_it_does_not_know(self) -> None:
        days = (("Information about Popular Times", *week()[0]), *week()[1:])

        assert len(parse_chart(chart(days=days), today=FRIDAY).bars) == 7 * 18 - 1

    def test_zero_bars_is_no_chart_data(self) -> None:
        with pytest.raises(NoChartData):
            parse_chart(chart(days=((),) * 7), today=FRIDAY)

    def test_missing_region_is_no_chart_data(self) -> None:
        with pytest.raises(NoChartData):
            parse_chart(chart(header="", days=()), today=FRIDAY)

    def test_rejects_a_week_that_is_not_seven_days(self) -> None:
        with pytest.raises(ChartShapeError, match="7 day containers"):
            parse_chart(chart(days=week()[:6]), today=FRIDAY)

    def test_rejects_a_header_that_is_not_today(self) -> None:
        with pytest.raises(ChartShapeError, match="header shows Friday"):
            parse_chart(chart(), today=4)

    def test_rejects_a_live_label_under_another_day(self) -> None:
        # Header still says Friday, but the live bar sits in Thursday's container:
        # the day order has shifted.
        days = tuple(day({}, live_at=9 if d == 4 else None) for d in range(7))

        with pytest.raises(ChartShapeError, match="live label is under Thursday"):
            parse_chart(chart(days=days), today=FRIDAY)

    def test_rejects_two_live_labels(self) -> None:
        days = tuple(day({}, live_at=9 if d in (4, FRIDAY) else None) for d in range(7))

        with pytest.raises(ChartShapeError, match="at most one live label"):
            parse_chart(chart(days=days), today=FRIDAY)

    def test_rejects_a_duplicate_bar(self) -> None:
        days = ((*week()[0], bar(50, 10)), *week()[1:])

        with pytest.raises(ChartShapeError, match="two bars"):
            parse_chart(chart(days=days), today=FRIDAY)

    def test_rejects_a_percentage_over_100(self) -> None:
        days = ((bar(101, 10),), *week()[1:])

        with pytest.raises(ChartShapeError, match="out of range"):
            parse_chart(chart(days=days), today=FRIDAY)
