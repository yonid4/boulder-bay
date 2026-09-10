import Foundation

/// The list shape returned by `GET /api/gyms`: reference data plus today's hours and the
/// latest live reading. `slug` is the public identifier throughout the API; the
/// database's bigint id never appears.
struct Gym: Codable, Identifiable, Hashable, Sendable {
    /// The most recent `busyness_snapshots` row. `busyPct` is nil when Google reported
    /// no live occupancy, which happens when a venue is quiet or closed.
    struct LiveReading: Codable, Hashable, Sendable {
        let busyPct: Int?
        let observedAt: Date

        enum CodingKeys: String, CodingKey {
            case busyPct = "busy_pct"
            case observedAt = "observed_at"
        }
    }

    let slug: String
    let name: String
    let brand: Brand
    let city: String
    let address: String?
    let latitude: Double
    let longitude: Double
    /// Where to fetch the gym's mark. `nil` until the backend serves `gym_logos`;
    /// `GymLogoView` falls back to initials.
    let logoURL: URL?
    let websiteURL: URL?
    let waiverURL: URL?
    let rates: GymRates
    /// `nil` when the gym has no `gym_hours` row for today.
    let hoursToday: HoursRange?
    let live: LiveReading?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, brand, city, address, latitude, longitude, rates, live
        case logoURL = "logo_url"
        case websiteURL = "website_url"
        case waiverURL = "waiver_url"
        case hoursToday = "hours_today"
    }
}
