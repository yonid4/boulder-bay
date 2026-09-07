import Foundation
import Testing

@testable import BoulderBay

struct GymDecodingTests {
    /// Mirrors the shape returned by `GET /api/gyms`.
    static let payload = Data(
        """
        {"data": [{
            "id": "dogpatch",
            "name": "Dogpatch Boulders",
            "brand": "Touchstone",
            "city": "SF",
            "lat": 37.7565,
            "lng": -122.3881,
            "rates": {"day": 30, "month": 95},
            "live": {"busy_pct": 54, "level": "Moderate"}
        }]}
        """.utf8
    )

    @Test func decodesGymEnvelopeFromBackendShape() throws {
        let gyms = try JSONDecoder()
            .decode(APIEnvelope<[Gym]>.self, from: Self.payload)
            .data

        #expect(gyms.count == 1)
        #expect(gyms[0].id == "dogpatch")
        #expect(gyms[0].live.busyPct == 54)
        #expect(gyms[0].rates.month == 95)
    }
}
