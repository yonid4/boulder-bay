import Foundation

struct Gym: Codable, Identifiable, Hashable, Sendable {
    struct Rates: Codable, Hashable, Sendable {
        let day: Int
        let month: Int
    }

    struct Live: Codable, Hashable, Sendable {
        let busyPct: Int
        let level: String

        enum CodingKeys: String, CodingKey {
            case busyPct = "busy_pct"
            case level
        }
    }

    let id: String
    let name: String
    let brand: String
    let city: String
    let lat: Double
    let lng: Double
    let rates: Rates
    let live: Live
}
