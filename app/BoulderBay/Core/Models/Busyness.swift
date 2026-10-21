import Foundation

enum BusynessLevel: String, Codable, Hashable, Sendable {
    case quiet
    case moderate
    case packed
}

enum BusynessSource: String, Codable, Hashable, Sendable {
    case live
    /// The mean of the live readings taken during an hour that is already over.
    case observed
    case forecast
}

struct ResolvedBusyness: Codable, Hashable, Sendable {
    let at: Date
    let isOpen: Bool
    let busyPct: Int?
    let level: BusynessLevel?
    let source: BusynessSource?
}

struct ForecastPoint: Codable, Hashable, Sendable {
    let startsAt: Date
    let endsAt: Date
    let busyPct: Int?
    let level: BusynessLevel?
}

struct BusynessForecast: Codable, Hashable, Sendable {
    let date: LocalDate
    let timezone: String
    let points: [ForecastPoint]
    let bestTime: ForecastPoint?
}
