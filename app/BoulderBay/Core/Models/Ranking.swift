import Foundation

struct RankedGym: Codable, Hashable, Sendable {
    let rank: Int
    let score: Double
    let travelMinutes: Double
    let isMember: Bool
    let gym: Gym
}

struct LocationRankings: Codable, Hashable, Sendable {
    let location: SavedLocation
    let rankedGyms: [RankedGym]
}

struct Rankings: Codable, Hashable, Sendable {
    let at: Date
    let locations: [LocationRankings]
}
