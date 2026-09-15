import Foundation
import Testing

@testable import BoulderBay

struct GymDecodingTests {
    /// Mirrors the shape returned by `GET /api/gyms`.
    static let payload = Data(
        """
        {"data": [
            {
                "slug": "dogpatch",
                "name": "Dogpatch Boulders",
                "brand": "touchstone",
                "city": "San Francisco",
                "latitude": 37.7567,
                "longitude": -122.3903,
                "logo_url": "http://localhost:8000/api/gyms/dogpatch/logo",
                "busyness": {
                    "at": "2026-09-13T18:00:00Z",
                    "is_open": true,
                    "busy_pct": 70,
                    "level": "packed",
                    "source": "forecast"
                }
            },
            {
                "slug": "mission",
                "name": "Mission Cliffs",
                "brand": "touchstone",
                "city": "San Francisco",
                "latitude": 37.7609,
                "longitude": -122.4128,
                "logo_url": null,
                "busyness": {
                    "at": "2026-09-13T18:00:00Z",
                    "is_open": false,
                    "busy_pct": null,
                    "level": null,
                    "source": null
                }
            }
        ]}
        """.utf8
    )

    @Test func decodesGymEnvelopeFromBackendShape() throws {
        let gyms = try APIClient.jsonDecoder
            .decode(APIEnvelope<[Gym]>.self, from: Self.payload)
            .data

        #expect(gyms.count == 2)
        #expect(gyms[0].id == "dogpatch")
        #expect(gyms[0].brand == .touchstone)
        #expect(gyms[0].latitude == 37.7567)
        #expect(gyms[0].longitude == -122.3903)
        #expect(gyms[0].logoUrl?.absoluteString == "http://localhost:8000/api/gyms/dogpatch/logo")
        #expect(gyms[0].busyness.at == Date(timeIntervalSince1970: 1_789_322_400))
        #expect(gyms[0].busyness.isOpen)
        #expect(gyms[0].busyness.busyPct == 70)
        #expect(gyms[0].busyness.level == .packed)
        #expect(gyms[0].busyness.source == .forecast)

        #expect(gyms[1].logoUrl == nil)
        #expect(!gyms[1].busyness.isOpen)
        #expect(gyms[1].busyness.busyPct == nil)
        #expect(gyms[1].busyness.level == nil)
        #expect(gyms[1].busyness.source == nil)
    }
}
