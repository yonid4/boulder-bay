import Foundation

enum GymBrand: String, Codable, Hashable, Sendable {
    case movement
    case touchstone
    case benchmark
    case independent
}

struct Gym: Codable, Identifiable, Hashable, Sendable {
    let slug: String
    let name: String
    let brand: GymBrand
    let city: String
    let latitude: Double
    let longitude: Double
    let logoUrl: URL?
    let busyness: ResolvedBusyness

    var id: String { slug }
}
