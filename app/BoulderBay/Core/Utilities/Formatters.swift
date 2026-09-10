import Foundation

/// Every gym is in America/Los_Angeles, and hours, forecasts and the time scrubber are
/// all clock times in that zone. One place decides what "today" and "this hour" mean.
enum BayArea {
    static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()

    /// 0 = Sunday, matching `gym_hours.day_of_week`.
    static func dayOfWeek(_ date: Date) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    static func hour(_ date: Date) -> Int {
        calendar.component(.hour, from: date)
    }

    /// Today at the start of `hour`, e.g. for `GET /api/rankings?at=`.
    static func date(today hour: Int, from now: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
    }
}

/// Display strings, matching the mockup's spellings exactly.
enum Format {
    /// `17` → "5 PM", `0` → "12 AM", `12` → "12 PM".
    static func hour(_ hour: Int) -> String {
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve) \(hour < 12 ? "AM" : "PM")"
    }

    /// "6 AM – 10 PM", the en dash the mockup uses.
    static func hoursRange(_ range: HoursRange) -> String {
        "\(clockTime(range.opensAt)) – \(clockTime(range.closesAt))"
    }

    /// "7 PM – 8 PM" for a one-hour window starting at `hour`.
    static func window(startingAt hour: Int) -> String {
        "\(Format.hour(hour)) – \(Format.hour((hour + 1) % 24))"
    }

    /// `ClockTime(15, 0)` → "3 PM"; `ClockTime(6, 30)` → "6:30 AM".
    static func clockTime(_ time: ClockTime) -> String {
        time.minute == 0
            ? hour(time.hour)
            : "\(time.hour % 12 == 0 ? 12 : time.hour % 12):\(String(format: "%02d", time.minute)) \(time.hour < 12 ? "AM" : "PM")"
    }

    /// `3000` → "$30"; `3350` → "$33.50".
    static func dollars(cents: Int) -> String {
        cents % 100 == 0 ? "$\(cents / 100)" : String(format: "$%.2f", Double(cents) / 100)
    }

    /// "8.3 mi"
    static func miles(_ miles: Double) -> String {
        String(format: "%.1f mi", miles)
    }

    /// "12 min"
    static func minutes(_ minutes: Int) -> String {
        "\(minutes) min"
    }

    /// "Open until 10 PM" / "Closed".
    static func openStatus(hoursToday: HoursRange?, at hour: Int) -> String {
        guard let hoursToday, hoursToday.contains(ClockTime(hour: hour)) else { return "Closed" }
        return "Open until \(clockTime(hoursToday.closesAt))"
    }
}
