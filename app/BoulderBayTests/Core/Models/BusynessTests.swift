import Testing

@testable import BoulderBay

struct BusynessLevelTests {
    @Test(arguments: [
        (0, BusynessLevel.quiet), (39, .quiet),
        (40, .moderate), (69, .moderate),
        (70, .packed), (100, .packed),
    ])
    func thresholdsMatchThePlan(percent: Int, expected: BusynessLevel) {
        #expect(BusynessLevel(percent: percent) == expected)
    }

    @Test func labelsLeadWithTheWord() {
        #expect(BusynessLevel.quiet.label == "Quiet")
        #expect(BusynessLevel.moderate.label == "Moderate")
        #expect(BusynessLevel.packed.label == "Packed")
    }
}

struct BusynessForecastTests {
    let forecast = [
        ForecastPoint(hour: 17, busyPct: 41),
        ForecastPoint(hour: 18, busyPct: 72),
        ForecastPoint(hour: 19, busyPct: 80),
        ForecastPoint(hour: 20, busyPct: 55),
        ForecastPoint(hour: 21, busyPct: 30),
        ForecastPoint(hour: 22, busyPct: 30),
    ]

    @Test func bestWindowIsTheQuietestFutureHour() {
        let best = BusynessForecast.bestWindow(in: forecast, after: 17)
        #expect(best?.hour == 21)
        #expect(best?.busyPct == 30)
        #expect(best?.level == .quiet)
    }

    @Test func tiesGoToTheEarlierHour() {
        // Only 21 and 22 remain, both at 30.
        #expect(BusynessForecast.bestWindow(in: forecast, after: 20)?.hour == 21)
    }

    @Test func currentHourIsNeverRecommended() {
        #expect(BusynessForecast.bestWindow(in: forecast, after: 21)?.hour == 22)
    }

    @Test func noFutureHourMeansNoWindow() {
        #expect(BusynessForecast.bestWindow(in: forecast, after: 22) == nil)
        #expect(BusynessForecast.bestWindow(in: [], after: 10) == nil)
    }

    @Test func busyPctLooksUpAnHour() {
        #expect(BusynessForecast.busyPct(in: forecast, at: 19) == 80)
        #expect(BusynessForecast.busyPct(in: forecast, at: 5) == nil)
    }
}

struct ClockTimeTests {
    @Test func parsesHourMinuteAndHourMinuteSecond() {
        #expect(ClockTime("15:00") == ClockTime(hour: 15))
        #expect(ClockTime("06:30:00") == ClockTime(hour: 6, minute: 30))
        #expect(ClockTime("24:00") == nil)
        #expect(ClockTime("noon") == nil)
    }

    @Test func rangeContainsIsOpenInclusiveCloseExclusive() {
        let range = HoursRange(opensAt: ClockTime(hour: 6), closesAt: ClockTime(hour: 22))
        #expect(range.contains(ClockTime(hour: 6)))
        #expect(range.contains(ClockTime(hour: 21, minute: 59)))
        #expect(!range.contains(ClockTime(hour: 22)))
        #expect(!range.contains(ClockTime(hour: 5, minute: 59)))
        #expect(range.openHours == Array(6..<22))
    }
}
