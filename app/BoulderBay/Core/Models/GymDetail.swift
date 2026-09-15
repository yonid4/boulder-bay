import Foundation

struct GymHours: Codable, Hashable, Sendable {
    let dayOfWeek: Int
    let opensAt: LocalTime
    let closesAt: LocalTime
}

struct GymRates: Codable, Hashable, Sendable {
    let dayPassCents: Int?
    let dayPassPeakCents: Int?
    let peakStartsAt: LocalTime?
    let monthlyCents: Int?
}

struct GymDetail: Codable, Hashable, Sendable {
    let gym: Gym
    let address: String?
    let timezone: String
    let websiteUrl: URL?
    let waiverUrl: URL?
    let hours: [GymHours]
    let rates: GymRates
    let forecast: BusynessForecast
}
