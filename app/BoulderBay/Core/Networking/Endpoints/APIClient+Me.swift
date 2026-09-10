import Foundation

/// `/api/me`, `/api/me/memberships`, `/api/me/locations`.
extension LiveAPIClient {
    func me() async throws -> UserProfile {
        try await send(.get("/api/me"), as: UserProfile.self)
    }

    func memberships() async throws -> [String] {
        try await send(.get("/api/me/memberships"), as: [String].self)
    }

    func updateMemberships(_ slugs: [String]) async throws -> [String] {
        try await send(
            .put("/api/me/memberships", json: MembershipsBody(gymSlugs: slugs)),
            as: [String].self
        )
    }

    func locations() async throws -> [SavedLocation] {
        try await send(.get("/api/me/locations"), as: [SavedLocation].self)
    }

    func createLocation(_ location: NewSavedLocation) async throws -> SavedLocation {
        try await send(.post("/api/me/locations", json: location), as: SavedLocation.self)
    }

    func deleteLocation(id: UUID) async throws {
        try await send(.delete("/api/me/locations/\(id.uuidString.lowercased())"))
    }
}

/// Body of `PUT /api/me/memberships`.
struct MembershipsBody: Codable, Hashable, Sendable {
    let gymSlugs: [String]

    enum CodingKeys: String, CodingKey {
        case gymSlugs = "gym_slugs"
    }
}
