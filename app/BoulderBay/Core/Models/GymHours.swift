/// One `gym_hours` row. `dayOfWeek` uses the database convention, **0 = Sunday**;
/// Swift's `Calendar.weekday` is 1-based, so callers subtract 1 (see `Formatters`).
struct GymHours: Codable, Hashable, Sendable {
    let dayOfWeek: Int
    let opensAt: ClockTime
    let closesAt: ClockTime

    enum CodingKeys: String, CodingKey {
        case dayOfWeek = "day_of_week"
        case opensAt = "opens_at"
        case closesAt = "closes_at"
    }

    var range: HoursRange { HoursRange(opensAt: opensAt, closesAt: closesAt) }
}
