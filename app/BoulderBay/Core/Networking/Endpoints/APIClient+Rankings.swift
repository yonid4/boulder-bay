import Foundation

/// `GET /api/rankings?location_id=…[&at=…]`.
extension LiveAPIClient {
    func rankings(locationID: UUID, at: Date?) async throws -> Rankings {
        var query = [URLQueryItem(name: "location_id", value: locationID.uuidString.lowercased())]
        if let at {
            query.append(URLQueryItem(name: "at", value: at.ISO8601Format()))
        }
        return try await send(.get("/api/rankings", query: query), as: Rankings.self)
    }
}
