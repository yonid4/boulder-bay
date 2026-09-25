"""Turn the Popular times chart's accessibility labels into a crowd reading.

Pure: the input is plain data a browser extracted, so this module never imports
Playwright and is fully unit-tested.

What the chart looks like (checked against the live page, September 2026):

- One container per weekday, always seven of them, in Sunday-first order. None is marked
  as the displayed one (no `aria-hidden`), so the order is the only day attribution.
- Every day has 18 hourly bars, 6 AM through 11 PM, whatever the gym's hours. Closed
  hours are rendered as 0% bars; filtering them out is the writer's job, because only
  `gym_hours` can tell a closed hour from a genuinely empty one.
- The current hour's bar carries the live label instead of an hourly one.
- The section header names the displayed day, which is today: "Fridays".

Because the order is taken on trust, `parse_chart` checks it against today twice: the
header's weekday, and the day the live label sits in, must both be the gym's local
weekday. Either mismatch raises `ChartShapeError` rather than writing a shifted week.
"""

import re
from dataclasses import dataclass, field

WEEKDAYS = ("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")

# The space before AM/PM is U+202F (narrow no-break space) on the live page.
HOURLY_LABEL = re.compile(r"^(\d{1,3})% busy at (\d{1,2})[ \u00a0\u202f](AM|PM)\.$")
LIVE_LABEL = re.compile(r"^Currently (\d{1,3})% busy, usually (\d{1,3})% busy\.$")
HEADER_WEEKDAY = re.compile(r"\b(" + "|".join(WEEKDAYS) + r")s?\b")


class NoChartData(Exception):
    """The page had no Popular times bars at all: a stunted load, or no chart."""


class ChartShapeError(Exception):
    """The chart is there but not in the shape this parser knows. Likely a DOM change."""


@dataclass(frozen=True)
class RawChart:
    """What the browser extracts from one place page."""

    place_name: str | None
    # The section's text, which names the displayed day ("Popular times\nFridays\n...").
    header: str
    # The aria-labels inside each day container, in DOM order.
    days: tuple[tuple[str, ...], ...]


@dataclass(frozen=True)
class CrowdReading:
    place_name: str | None
    live_pct: int | None
    typical_pct: int | None
    # (day_of_week, hour_of_day) -> percent, Sunday as day zero. Includes closed hours.
    bars: dict[tuple[int, int], int] = field(default_factory=dict)


def hour_of_day(hour: int, meridiem: str) -> int:
    """12-hour clock to 0-23: 12 AM is 0 and 12 PM is 12."""

    if not 1 <= hour <= 12:
        raise ChartShapeError(f"hour {hour} is not on a 12-hour clock")
    return hour % 12 + (12 if meridiem == "PM" else 0)


def percent(text: str) -> int:
    value = int(text)
    if value > 100:
        raise ChartShapeError(f"{value}% is out of range")
    return value


def header_weekday(header: str) -> int:
    """The one weekday named in the section header, Sunday as zero."""

    named = {match.group(1) for match in HEADER_WEEKDAY.finditer(header)}
    if len(named) != 1:
        raise ChartShapeError(f"expected one weekday in the header, found {sorted(named)}")
    return WEEKDAYS.index(named.pop())


def parse_chart(raw: RawChart, *, today: int) -> CrowdReading:
    """Parse one extracted chart. `today` is the gym's local weekday, Sunday as zero."""

    bars: dict[tuple[int, int], int] = {}
    live: list[tuple[int, int, int]] = []  # (day, live_pct, typical_pct)

    for day, labels in enumerate(raw.days):
        for label in labels:
            if match := HOURLY_LABEL.match(label):
                slot = (day, hour_of_day(int(match.group(2)), match.group(3)))
                if slot in bars:
                    raise ChartShapeError(f"two bars for day {slot[0]} hour {slot[1]}")
                bars[slot] = percent(match.group(1))
            elif match := LIVE_LABEL.match(label):
                live.append((day, percent(match.group(1)), percent(match.group(2))))

    if not bars:
        raise NoChartData("no Popular times bars on the page")
    if len(raw.days) != len(WEEKDAYS):
        raise ChartShapeError(f"expected 7 day containers, found {len(raw.days)}")

    displayed = header_weekday(raw.header)
    if displayed != today:
        raise ChartShapeError(
            f"header shows {WEEKDAYS[displayed]} but it is {WEEKDAYS[today]} at the gym"
        )
    if len(live) > 1:
        raise ChartShapeError(f"expected at most one live label, found {len(live)}")

    live_pct = typical_pct = None
    if live:
        live_day, live_pct, typical_pct = live[0]
        if live_day != today:
            raise ChartShapeError(
                f"live label is under {WEEKDAYS[live_day]} but it is {WEEKDAYS[today]}"
            )

    return CrowdReading(
        place_name=raw.place_name, live_pct=live_pct, typical_pct=typical_pct, bars=bars
    )
