import Foundation

/// One row of `GET /api/rankings`. `busyPct` is the live reading when `at` is now and
/// the curve's prediction otherwise; nil when neither exists.
struct RankingEntry: Codable, Identifiable, Hashable, Sendable {
    let slug: String
    let rank: Int
    let score: Double
    let busyPct: Int?
    let isOpen: Bool
    let isMember: Bool
    let travelMinutes: Int
    let distanceMiles: Double

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, rank, score
        case busyPct = "busy_pct"
        case isOpen = "is_open"
        case isMember = "is_member"
        case travelMinutes = "travel_minutes"
        case distanceMiles = "distance_miles"
    }

    var level: BusynessLevel? { busyPct.map(BusynessLevel.init(percent:)) }
}

/// The full response: all sixteen gyms scored from one saved location at one moment,
/// already sorted best-first.
struct Rankings: Codable, Hashable, Sendable {
    let locationID: UUID
    let at: Date
    let gyms: [RankingEntry]

    enum CodingKeys: String, CodingKey {
        case locationID = "location_id"
        case at, gyms
    }

    var best: RankingEntry? { gyms.first }
}
