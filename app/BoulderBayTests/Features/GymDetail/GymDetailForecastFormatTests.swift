import Foundation
import Testing

@testable import BoulderBay

struct GymDetailForecastFormatTests {
    private let at = GymDetailFixtures.at

    private func busyness(
        at: Date = GymDetailFixtures.at, isOpen: Bool = true, percent: Int? = 42
    ) -> ResolvedBusyness {
        ResolvedBusyness(
            at: at, isOpen: isOpen, busyPct: percent, level: percent == nil ? nil : .moderate,
            source: percent == nil ? nil : .live
        )
    }

    // MARK: Bars

    @Test func anHourWithNoReadingDrawsNoBarRatherThanZero() {
        let forecast = GymDetailFixtures.forecast(points: [
            GymDetailFixtures.point(hoursAfterAt: 0),
            GymDetailFixtures.point(hoursAfterAt: 1, percent: nil, level: nil, source: nil),
        ])
        let bars = GymDetailFormat.forecastBars(forecast, at: at, now: at)
        #expect(bars.map(\.id) == [at])
    }

    @Test func aZeroPercentHourStillHasAVisibleBar() {
        let forecast = GymDetailFixtures.forecast(points: [
            GymDetailFixtures.point(hoursAfterAt: 0, percent: 0)
        ])
        #expect(GymDetailFormat.forecastBars(forecast, at: at, now: at).first?.height == 6)
    }

    /// Four hours in a row, the first ending at `at`.
    private var fourHours: BusynessForecast {
        GymDetailFixtures.forecast(
            points: (-1...2).map { GymDetailFixtures.point(hoursAfterAt: $0) }
        )
    }

    @Test func onTheCurrentHourEarlierHoursAreDimmedAndLaterOnesNot() {
        let bars = GymDetailFormat.forecastBars(fourHours, at: at, now: at)
        #expect(bars.map(\.opacity) == [0.3, 1, 0.8, 0.8])
    }

    /// Hours between now and a later selected hour haven't happened, so they aren't dimmed.
    @Test func aLaterSelectedHourDimsOnlyTheHoursBeforeNow() {
        let later = at.addingTimeInterval(2 * 3600)
        let bars = GymDetailFormat.forecastBars(fourHours, at: later, now: at)
        #expect(bars.map(\.opacity) == [0.3, 0.8, 0.8, 1])
    }

    /// Hours that are over stay dimmed either side of an earlier selected hour, which alone is
    /// full strength.
    @Test func anEarlierSelectedHourIsFullStrengthAmongDimmedOnes() {
        let now = at.addingTimeInterval(2 * 3600)
        let bars = GymDetailFormat.forecastBars(fourHours, at: at, now: now)
        #expect(bars.map(\.opacity) == [0.3, 1, 0.3, 0.8])
    }

    /// The hour in progress hasn't ended, so it isn't past.
    @Test func theHourInProgressIsNotDimmed() {
        let midHour = at.addingTimeInterval(1800)
        let later = at.addingTimeInterval(2 * 3600)
        let bars = GymDetailFormat.forecastBars(fourHours, at: later, now: midHour)
        #expect(bars.map(\.opacity) == [0.3, 0.8, 0.8, 1])
    }

    /// The fall DST change repeats 1 AM: same label, different instants.
    @Test func aRepeatedHourOnADSTDayKeepsTwoSeparateBars() {
        // 2026-11-01 08:00 UTC, which is 1 AM PDT.
        let fallBack = Date(timeIntervalSince1970: 1_793_520_000)
        let points = [0.0, 3600].map { offset in
            ForecastPoint(
                startsAt: fallBack.addingTimeInterval(offset),
                endsAt: fallBack.addingTimeInterval(offset + 3600),
                busyPct: 30,
                level: .quiet,
                source: .forecast
            )
        }
        let bars = GymDetailFormat.forecastBars(
            GymDetailFixtures.forecast(points: points), at: fallBack, now: fallBack
        )
        #expect(bars.map(\.hourLabel) == ["1 AM", "1 AM"])
        #expect(Set(bars.map(\.id)).count == 2)
    }

    // MARK: Ticks

    @Test func ticksFallOnEveryFourthHourAndTheLast() {
        let forecast = GymDetailFixtures.forecast(
            points: (0..<10).map { GymDetailFixtures.point(hoursAfterAt: $0) }
        )
        // Hour 8 sits right next to the last hour, so its label gives way.
        let expected = [0, 4, 9].map { at.addingTimeInterval(Double($0) * 3600 + 1800) }
        #expect(GymDetailFormat.forecastTicks(forecast) == expected)
    }

    @Test func noHoursMeansNoTicks() {
        #expect(GymDetailFormat.forecastTicks(GymDetailFixtures.forecast(points: [])).isEmpty)
    }

    // MARK: Best time

    @Test func aBestTimeShowsItsHourThenItsWordAndPercentage() {
        let summary = GymDetailFormat.bestTime(
            GymDetailFixtures.fullWithBestTime.forecast, busyness: busyness(), isNow: true
        )
        #expect(summary == BestTimeSummary(headline: "4 PM – 5 PM", note: "quiet, about 28%"))
    }

    @Test func aBestTimeWithNoReadingLeavesTheNoteOut() {
        let forecast = GymDetailFixtures.forecast(
            points: [GymDetailFixtures.point(hoursAfterAt: 0)],
            bestTime: GymDetailFixtures.point(
                hoursAfterAt: 1, percent: nil, level: nil, source: nil
            )
        )
        let summary = GymDetailFormat.bestTime(forecast, busyness: busyness(), isNow: true)
        #expect(summary == BestTimeSummary(headline: "12 PM – 1 PM", note: nil))
    }

    @Test func theLastOpenHourClosesSoon() {
        let forecast = GymDetailFixtures.forecast(points: [GymDetailFixtures.point(hoursAfterAt: 0)])
        #expect(
            GymDetailFormat.bestTime(forecast, busyness: busyness(), isNow: true)
                == BestTimeSummary(headline: "Closes soon", note: "42% now")
        )
        #expect(
            GymDetailFormat.bestTime(forecast, busyness: busyness(), isNow: false)
                == BestTimeSummary(headline: "Closes soon", note: "42% at 11 AM")
        )
        #expect(
            GymDetailFormat.bestTime(forecast, busyness: busyness(percent: nil), isNow: true)
                == BestTimeSummary(headline: "Closes soon", note: nil)
        )
    }

    @Test func laterHoursWithNoForecastAreNotClosingSoon() {
        let summary = GymDetailFormat.bestTime(
            GymDetailFixtures.full.forecast, busyness: busyness(), isNow: true
        )
        #expect(summary == BestTimeSummary(headline: "No forecast left", note: "today"))
    }

    @Test func aHourAfterCloseIsNotClosingSoon() {
        let forecast = GymDetailFixtures.forecast(points: [GymDetailFixtures.point(hoursAfterAt: -2)])
        let summary = GymDetailFormat.bestTime(
            forecast, busyness: busyness(isOpen: false, percent: nil), isNow: false
        )
        #expect(summary == BestTimeSummary(headline: "No forecast left", note: "today"))
    }

    @Test func aDayWithNoOpenHoursHasNoBestTime() {
        let summary = GymDetailFormat.bestTime(
            GymDetailFixtures.sparse.forecast, busyness: busyness(), isNow: true
        )
        #expect(summary == nil)
    }
}
