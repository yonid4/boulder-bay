import Foundation

struct RankedGym: Codable, Hashable, Sendable {
    let rank: Int
    /// Unrounded; round it before showing it.
    let score: Double
    let travelMinutes: Double
    let gym: Gym
}

/// One place's rankings. Only gyms open at `at` are in `rankedGyms`, and it can be empty: nothing
/// in range is open then, or nothing is within range at all.
struct Rankings: Codable, Hashable, Sendable {
    /// The server's exact time when the request left `at` out, so don't label an hour from it.
    let at: Date
    let location: SavedLocation
    let rankedGyms: [RankedGym]
}
