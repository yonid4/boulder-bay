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

/// What the "Best time to go" column says.
struct BestTimeSummary: Equatable {
    /// "4 PM – 5 PM", "Closes soon" or "No forecast left".
    let headline: String
    /// "quiet, about 28%", "42% now" or "today".
    let note: String?
}

/// One drawn bar of the forecast chart. An hour with no reading has none.
struct ForecastBar: Equatable, Identifiable {
    /// The point's `starts_at`, which stays unique on a DST day.
    let id: Date
    /// Where the bar starts and ends, inset from its hour so neighbouring bars have a gap.
    let start: Date
    let end: Date
    /// In points. A 0% hour keeps a stub, so it can't be mistaken for an hour with no reading.
    let height: Int
    let level: BusynessLevel
    let opacity: Double
    /// "7 PM".
    let hourLabel: String
    /// "Quiet, 32%".
    let valueLabel: String
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

    // MARK: Forecast

    /// Only hours that have ended by `now` are dimmed, wherever the selected hour `at` is. This
    /// compares times because `source` can't mark the past: a finished hour with no readings falls
    /// back to the curve and says `forecast`.
    static func forecastBars(_ forecast: BusynessForecast, at: Date, now: Date) -> [ForecastBar] {
        forecast.points.compactMap { point in
            guard let percent = point.busyPct, let level = point.level else { return nil }
            let isSelected = point.startsAt <= at && at < point.endsAt
            let isPast = point.endsAt <= now
            let inset = point.endsAt.timeIntervalSince(point.startsAt) * 0.04
            return ForecastBar(
                id: point.startsAt,
                start: point.startsAt.addingTimeInterval(inset),
                end: point.endsAt.addingTimeInterval(-inset),
                height: 6 + min(max(percent, 0), 100) * 78 / 100,
                level: level,
                opacity: isSelected ? 1 : isPast ? 0.3 : 0.8,
                hourLabel: hourLabel(for: point.startsAt, timeZone: forecast.timezone),
                valueLabel: "\(level.rawValue.capitalized), \(percent)%"
            )
        }
    }

    /// The middle of every fourth hour and of the last one, where the chart's labels go. A fourth
    /// hour too close to the last is left out, so their labels can't overlap.
    static func forecastTicks(_ forecast: BusynessForecast) -> [Date] {
        let points = forecast.points
        let lastIndex = points.count - 1
        return points.indices
            .filter { $0 == lastIndex || ($0 % 4 == 0 && lastIndex - $0 > 1) }
            .map { index in
                let point = points[index]
                return point.startsAt.addingTimeInterval(
                    point.endsAt.timeIntervalSince(point.startsAt) / 2
                )
            }
    }

    /// `nil` when the day has no open hours. A null `best_time` means no later hour has a
    /// forecast, which reads as "Closes soon" only in the gym's last open hour.
    static func bestTime(
        _ forecast: BusynessForecast, busyness: ResolvedBusyness, isNow: Bool
    ) -> BestTimeSummary? {
        guard !forecast.points.isEmpty else { return nil }
        let timeZone = forecast.timezone
        if let best = forecast.bestTime {
            let start = hourLabel(for: best.startsAt, timeZone: timeZone)
            let end = hourLabel(for: best.endsAt, timeZone: timeZone)
            let note = best.level.flatMap { level in
                best.busyPct.map { "\(level.rawValue), about \($0)%" }
            }
            return BestTimeSummary(headline: "\(start) – \(end)", note: note)
        }
        let hasLaterHour = forecast.points.contains { $0.startsAt > busyness.at }
        guard busyness.isOpen, !hasLaterHour else {
            return BestTimeSummary(headline: "No forecast left", note: "today")
        }
        let note = busyness.busyPct.map { percent in
            let when = isNow ? "now" : "at \(hourLabel(for: busyness.at, timeZone: timeZone))"
            return "\(percent)% \(when)"
        }
        return BestTimeSummary(headline: "Closes soon", note: note)
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

    static func clock(hour: Int, minute: Int) -> String {
        let twelveHour = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return minute == 0
            ? "\(twelveHour) \(suffix)"
            : "\(twelveHour):\(String(format: "%02d", minute)) \(suffix)"
    }
}
