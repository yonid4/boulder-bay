import Foundation

/// A `saved_locations` row. v1 creates exactly one, during onboarding, but the shape
/// keeps `isDefault` so the store and API contract survive v2's multi-location work.
struct SavedLocation: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let label: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let isDefault: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, label, address, latitude, longitude
        case isDefault = "is_default"
        case createdAt = "created_at"
    }
}

/// Body of `POST /api/me/locations`.
struct NewSavedLocation: Codable, Hashable, Sendable {
    let label: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case label, address, latitude, longitude
        case isDefault = "is_default"
    }
}
