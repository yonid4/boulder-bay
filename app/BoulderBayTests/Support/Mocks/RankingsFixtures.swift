import Foundation

/// Backend-shaped `GET /api/rankings` bodies.
enum RankingsFixtures {
    static let homeID = UUID(uuidString: "d16878be-c4bc-462f-8929-c464b6a5efad")!

    /// One ranked row per slug, in the order given.
    static func body(
        locationID: UUID = homeID, label: String = "Home", slugs: [String]
    ) -> Data {
        let rows = slugs.enumerated().map { index, slug in
            """
            {"rank": \(index + 1), "score": \(80 - index), "travel_minutes": \(10 + index), "gym": {
                "slug": "\(slug)", "name": "\(slug)", "brand": "independent", "city": "Oakland",
                "latitude": 37.8, "longitude": -122.27, "logo_url": null, "is_member": false,
                "busyness": {"at": "2026-09-13T18:00:00Z", "is_open": true, "busy_pct": 30,
                    "level": "quiet", "source": "forecast"}
            }}
            """
        }
        return Data(
            """
            {"data": {
                "at": "2026-09-13T18:00:00Z",
                "location": {
                    "id": "\(locationID.uuidString.lowercased())", "label": "\(label)",
                    "address": null, "latitude": 37.8, "longitude": -122.2,
                    "is_default": true, "kind": "home"
                },
                "ranked_gyms": [\(rows.joined(separator: ", "))]
            }}
            """.utf8
        )
    }
}
