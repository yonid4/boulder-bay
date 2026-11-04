import Foundation

/// What the Busyness section says, split from the view so every case can be tested.
struct BusynessSummary: Equatable {
    /// "Right now" or "At 7 PM".
    let title: String
    /// The crowd level's word, or "Closed" / "No forecast".
    let headline: String
    /// "32% of capacity"; `nil` without a reading, which is never drawn as 0.
    let detail: String?
    let level: BusynessLevel?
    let percent: Int?
}

/// One line of the expanded week.
struct DayHours: Equatable, Identifiable {
    /// Sunday is day zero, matching `GymHours.dayOfWeek`.
    let dayOfWeek: Int
    let name: String
    /// "6 AM – 11 PM", or "Closed" for a day with no row.
    let text: String
    let isToday: Bool

    var id: Int { dayOfWeek }
}

/// The Rates section's lines. A `nil` line is left out.
struct RateLines: Equatable {
    /// "Day pass $30 before 3 PM · $35 after", or "Day pass $30".
    let dayPass: String?
    /// "Monthly $130".
    let monthly: String?

    var isEmpty: Bool { dayPass == nil && monthly == nil }
}

/// The pure text behind the detail screen. Everything here reads in the gym's local time,
/// which is what `LocalTime` and `LocalDate` already hold.
enum GymDetailFormat {
    private static let dayNames = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    // MARK: Busyness

    /// - Parameters:
    ///   - isNow: whether the selected hour is the current one (`AppModel.isSelectedHourNow`).
    ///   - timeZone: the gym's timezone identifier, for naming the hour `busyness.at` is in.
    static func busyness(
        _ busyness: ResolvedBusyness, isNow: Bool, timeZone: String
    ) -> BusynessSummary {
        let title = isNow ? "Right now" : "At \(hourLabel(for: busyness.at, timeZone: timeZone))"
        guard busyness.isOpen else {
            return BusynessSummary(
                title: title, headline: "Closed", detail: nil, level: nil, percent: nil
            )
        }
        guard let level = busyness.level, let percent = busyness.busyPct else {
            return BusynessSummary(
                title: title, headline: "No forecast", detail: nil, level: nil, percent: nil
            )
        }
        return BusynessSummary(
            title: title,
            headline: level.rawValue.capitalized,
            detail: "\(percent)% of capacity",
            level: level,
            percent: percent
        )
    }

    /// "7 PM": the hour `date` falls in at the gym.
    static func hourLabel(for date: Date, timeZone: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        return clock(hour: calendar.component(.hour, from: date), minute: 0)
    }

    // MARK: Hours

    /// The day of the week of `date`, with Sunday as day zero like `GymHours.dayOfWeek`.
    static func dayOfWeek(of date: LocalDate) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(year: date.year, month: date.month, day: date.day)
        return calendar.date(from: components).map { calendar.component(.weekday, from: $0) - 1 }
    }

    /// All seven days, Sunday first. `today` is the gym's local date (`forecast.date`), not the
    /// device's. A day with no row is closed, as the backend treats it.
    static func week(_ hours: [GymHours], today: LocalDate) -> [DayHours] {
        let todayIndex = dayOfWeek(of: today)
        return dayNames.indices.map { day in
            let row = hours.first { $0.dayOfWeek == day }
            return DayHours(
                dayOfWeek: day,
                name: dayNames[day],
                text: row.map { "\(clock($0.opensAt)) – \(clock($0.closesAt))" } ?? "Closed",
                isToday: day == todayIndex
            )
        }
    }

    /// Today's line from `week(_:today:)`.
    static func todayHours(_ hours: [GymHours], today: LocalDate) -> String {
        week(hours, today: today).first(where: \.isToday)?.text ?? "Closed"
    }

    // MARK: Rates

    static func rates(_ rates: GymRates) -> RateLines {
        RateLines(
            dayPass: dayPass(rates),
            monthly: rates.monthlyCents.map { "Monthly \(price(cents: $0))" }
        )
    }

    /// Tiered only with a peak price and the time it starts. A peak price with no base price
    /// says nothing about what a day pass costs, so it's left out.
    private static func dayPass(_ rates: GymRates) -> String? {
        guard let base = rates.dayPassCents else { return nil }
        guard let peak = rates.dayPassPeakCents, let start = rates.peakStartsAt else {
            return "Day pass \(price(cents: base))"
        }
        return "Day pass \(price(cents: base)) before \(clock(start)) · \(price(cents: peak)) after"
    }

    /// "$30", or "$32.50" when there are cents to show.
    static func price(cents: Int) -> String {
        let remainder = cents % 100
        return remainder == 0
            ? "$\(cents / 100)"
            : "$\(cents / 100).\(String(format: "%02d", remainder))"
    }

    // MARK: Clock

    /// "3 PM", or "3:30 PM" when the minutes matter.
    static func clock(_ time: LocalTime) -> String {
        clock(hour: time.hour, minute: time.minute)
    }

    private static func clock(hour: Int, minute: Int) -> String {
        let twelveHour = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return minute == 0
            ? "\(twelveHour) \(suffix)"
            : "\(twelveHour):\(String(format: "%02d", minute)) \(suffix)"
    }
}
