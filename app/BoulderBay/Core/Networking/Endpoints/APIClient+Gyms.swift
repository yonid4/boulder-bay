import Foundation

/// `GET /api/gyms` and `GET /api/gyms/{slug}`.
extension LiveAPIClient {
    func gyms() async throws -> [Gym] {
        try await send(.get("/api/gyms"), as: [Gym].self)
    }

    func gym(slug: String) async throws -> GymDetail {
        try await send(.get("/api/gyms/\(slug)"), as: GymDetail.self)
    }
}
