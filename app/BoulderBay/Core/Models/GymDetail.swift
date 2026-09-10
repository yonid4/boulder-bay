import Foundation

/// `GET /api/gyms/{slug}`: everything in the list shape, plus the full week of hours and
/// today's forecast. The JSON is flat — the `Gym` fields sit beside `hours` and
/// `forecast` — so this decodes the summary from the same container.
struct GymDetail: Codable, Identifiable, Hashable, Sendable {
    let gym: Gym
    /// All seven `gym_hours` rows, `dayOfWeek` 0 = Sunday.
    let hours: [GymHours]
    /// One point per open hour today, from `busyness_curves`. Hours Google has no bar
    /// for are absent rather than zero.
    let forecast: [ForecastPoint]

    var id: String { gym.slug }

    init(gym: Gym, hours: [GymHours], forecast: [ForecastPoint]) {
        self.gym = gym
        self.hours = hours
        self.forecast = forecast
    }

    enum CodingKeys: String, CodingKey {
        case hours, forecast
    }

    init(from decoder: any Decoder) throws {
        gym = try Gym(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hours = try container.decode([GymHours].self, forKey: .hours)
        forecast = try container.decode([ForecastPoint].self, forKey: .forecast)
    }

    func encode(to encoder: any Encoder) throws {
        try gym.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hours, forKey: .hours)
        try container.encode(forecast, forKey: .forecast)
    }

    /// Hours for a given weekday (0 = Sunday), if the gym opens that day.
    func hours(on dayOfWeek: Int) -> HoursRange? {
        hours.first { $0.dayOfWeek == dayOfWeek }?.range
    }
}
