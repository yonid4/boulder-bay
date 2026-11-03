import Foundation
import Testing

@testable import BoulderBay

struct GymDetailFormatTests {
    private let losAngeles = "America/Los_Angeles"

    // MARK: Busyness

    private func busyness(
        isOpen: Bool = true, percent: Int? = nil, level: BusynessLevel? = nil
    ) -> ResolvedBusyness {
        ResolvedBusyness(
            at: GymDetailFixtures.at, isOpen: isOpen, busyPct: percent, level: level,
            source: percent == nil ? nil : .live
        )
    }

    @Test func aReadingLeadsWithTheWordThenThePercentage() {
        let summary = GymDetailFormat.busyness(
            busyness(percent: 32, level: .quiet), isNow: true, timeZone: losAngeles
        )
        #expect(summary.title == "Right now")
        #expect(summary.headline == "Quiet")
        #expect(summary.detail == "32% of capacity")
        #expect(summary.level == .quiet)
        #expect(summary.percent == 32)
    }

    @Test func anotherHourIsNamedInTheGymsLocalTime() {
        let summary = GymDetailFormat.busyness(
            busyness(percent: 80, level: .packed), isNow: false, timeZone: losAngeles
        )
        #expect(summary.title == "At 11 AM")
        #expect(summary.headline == "Packed")
    }

    @Test func aClosedGymSaysClosedEvenWithAStrayReading() {
        let summary = GymDetailFormat.busyness(
            busyness(isOpen: false, percent: 10, level: .quiet), isNow: true, timeZone: losAngeles
        )
        #expect(summary.headline == "Closed")
        #expect(summary.detail == nil)
        #expect(summary.percent == nil)
    }

    @Test func anOpenGymWithoutAReadingIsNeverZero() {
        let summary = GymDetailFormat.busyness(busyness(), isNow: false, timeZone: losAngeles)
        #expect(summary.headline == "No forecast")
        #expect(summary.detail == nil)
        #expect(summary.percent == nil)
    }

    @Test func zeroPercentIsAReading() {
        let summary = GymDetailFormat.busyness(
            busyness(percent: 0, level: .quiet), isNow: true, timeZone: losAngeles
        )
        #expect(summary.detail == "0% of capacity")
        #expect(summary.percent == 0)
    }

    // MARK: Hours

    private func hours(_ day: Int, _ opens: Int, _ closes: Int, closesMinute: Int = 0) -> GymHours {
        GymHours(
            dayOfWeek: day,
            opensAt: LocalTime(hour: opens, minute: 0, second: 0)!,
            closesAt: LocalTime(hour: closes, minute: closesMinute, second: 0)!
        )
    }

    @Test(arguments: [
        (2026, 9, 13, 0),  // Sunday
        (2026, 9, 14, 1),
        (2026, 9, 19, 6),  // Saturday
        (2028, 2, 29, 2),  // Leap day, a Tuesday
    ])
    func dayOfWeekCountsFromSunday(year: Int, month: Int, day: Int, expected: Int) {
        let date = LocalDate(year: year, month: month, day: day)!
        #expect(GymDetailFormat.dayOfWeek(of: date) == expected)
    }

    @Test func todaysHoursComeFromTheGivenDateNotTheDevice() {
        let rows = [hours(0, 8, 20), hours(1, 6, 23)]
        #expect(GymDetailFormat.todayHours(rows, today: GymDetailFixtures.sunday) == "8 AM – 8 PM")
        #expect(
            GymDetailFormat.todayHours(rows, today: LocalDate(year: 2026, month: 9, day: 14)!)
                == "6 AM – 11 PM"
        )
    }

    @Test func aDayWithNoRowIsClosed() {
        let rows = [hours(1, 6, 23)]
        #expect(GymDetailFormat.todayHours(rows, today: GymDetailFixtures.sunday) == "Closed")
    }

    @Test func theWeekHasSevenDaysSundayFirstWithOnlyTodayMarked() {
        let week = GymDetailFormat.week(
            [hours(1, 6, 22, closesMinute: 30)], today: GymDetailFixtures.sunday
        )
        #expect(week.map(\.dayOfWeek) == Array(0...6))
        #expect(week.map(\.name).first == "Sunday")
        #expect(week.filter(\.isToday).map(\.name) == ["Sunday"])
        #expect(week[0].text == "Closed")
        #expect(week[1].text == "6 AM – 10:30 PM")
    }

    @Test func clockHandlesNoonAndMidnight() {
        #expect(GymDetailFormat.clock(LocalTime(hour: 0, minute: 0, second: 0)!) == "12 AM")
        #expect(GymDetailFormat.clock(LocalTime(hour: 12, minute: 0, second: 0)!) == "12 PM")
        #expect(GymDetailFormat.clock(LocalTime(hour: 15, minute: 5, second: 0)!) == "3:05 PM")
    }

    // MARK: Rates

    @Test func tieredRatesNameTheTimeTheyChange() {
        let lines = GymDetailFormat.rates(
            GymRates(
                dayPassCents: 3000,
                dayPassPeakCents: 3500,
                peakStartsAt: LocalTime(hour: 15, minute: 0, second: 0),
                monthlyCents: 13000
            )
        )
        #expect(lines.dayPass == "Day pass $30 before 3 PM · $35 after")
        #expect(lines.monthly == "Monthly $130")
        #expect(!lines.isEmpty)
    }

    @Test func aFlatRateIsOnePrice() {
        let lines = GymDetailFormat.rates(
            GymRates(
                dayPassCents: 2800, dayPassPeakCents: nil, peakStartsAt: nil, monthlyCents: nil
            )
        )
        #expect(lines.dayPass == "Day pass $28")
        #expect(lines.monthly == nil)
    }

    @Test func aPeakPriceWithoutItsStartTimeFallsBackToTheBasePrice() {
        let lines = GymDetailFormat.rates(
            GymRates(
                dayPassCents: 3000, dayPassPeakCents: 3500, peakStartsAt: nil, monthlyCents: nil
            )
        )
        #expect(lines.dayPass == "Day pass $30")
    }

    @Test func monthlyAloneOmitsTheDayPass() {
        let lines = GymDetailFormat.rates(
            GymRates(
                dayPassCents: nil,
                dayPassPeakCents: 3500,
                peakStartsAt: LocalTime(hour: 15, minute: 0, second: 0),
                monthlyCents: 10900
            )
        )
        #expect(lines.dayPass == nil)
        #expect(lines.monthly == "Monthly $109")
    }

    @Test func allNullRatesAreEmpty() {
        let lines = GymDetailFormat.rates(
            GymRates(dayPassCents: nil, dayPassPeakCents: nil, peakStartsAt: nil, monthlyCents: nil)
        )
        #expect(lines.isEmpty)
    }

    @Test func pricesShowCentsOnlyWhenThereAreAny() {
        #expect(GymDetailFormat.price(cents: 3000) == "$30")
        #expect(GymDetailFormat.price(cents: 3250) == "$32.50")
        #expect(GymDetailFormat.price(cents: 3205) == "$32.05")
    }
}
