import Foundation
import Testing

@testable import BoulderBay

/// Every fixture in `Support/Fixtures/` decodes into its model, and the fields the
/// screens depend on come through with the right values.
struct PayloadDecodingTests {
    @Test func gymsListDecodesBothPopulatedAndSparseRows() throws {
        let gyms = try Fixture.decode("gyms", as: [Gym].self)

        #expect(gyms.count == 2)
        let dogpatch = try #require(gyms.first { $0.slug == "dogpatch" })
        #expect(dogpatch.id == "dogpatch")
        #expect(dogpatch.brand == .touchstone)
        #expect(dogpatch.logoURL?.absoluteString == "http://localhost:8000/api/logos/2")
        #expect(dogpatch.rates.dayPassCents == 3000)
        #expect(dogpatch.rates.dayPassPeakCents == 3500)
        #expect(dogpatch.rates.peakStartsAt == ClockTime(hour: 15))
        #expect(dogpatch.rates.hasPeakTier)
        #expect(dogpatch.hoursToday == HoursRange(opensAt: ClockTime(hour: 7), closesAt: ClockTime(hour: 23)))
        #expect(dogpatch.live?.busyPct == 54)

        let mosaic = try #require(gyms.first { $0.slug == "mosaic" })
        #expect(mosaic.brand == .independent)
        #expect(mosaic.logoURL == nil)
        #expect(mosaic.waiverURL == nil)
        #expect(!mosaic.rates.hasPeakTier)
        #expect(mosaic.hoursToday == nil)
        #expect(mosaic.live == nil)
    }

    @Test func gymDetailDecodesFlatSummaryPlusHoursAndForecast() throws {
        let detail = try Fixture.decode("gym_detail", as: GymDetail.self)

        #expect(detail.id == "mv-belmont")
        #expect(detail.gym.name == "Movement Belmont")
        #expect(detail.gym.brand == .movement)
        #expect(detail.hours.count == 7)
        #expect(detail.hours(on: 0) == HoursRange(opensAt: ClockTime(hour: 8), closesAt: ClockTime(hour: 18)))
        #expect(detail.hours(on: 6)?.closesAt == ClockTime(hour: 20))
        #expect(detail.forecast.map(\.hour) == [17, 18, 19, 20, 21, 22])
        #expect(detail.forecast.first?.busyPct == 41)
    }

    @Test func gymDetailRoundTripsThroughEncoding() throws {
        let fixture = try Fixture.decode("gym_detail", as: GymDetail.self)
        // The encoder writes whole seconds, so round-trip a whole-second reading.
        let gym = Gym(
            slug: fixture.gym.slug, name: fixture.gym.name, brand: fixture.gym.brand,
            city: fixture.gym.city, address: fixture.gym.address,
            latitude: fixture.gym.latitude, longitude: fixture.gym.longitude,
            logoURL: fixture.gym.logoURL, websiteURL: fixture.gym.websiteURL,
            waiverURL: fixture.gym.waiverURL, rates: fixture.gym.rates,
            hoursToday: fixture.gym.hoursToday,
            live: Gym.LiveReading(busyPct: 41, observedAt: Date(timeIntervalSince1970: 1_789_000_000))
        )
        let detail = GymDetail(gym: gym, hours: fixture.hours, forecast: fixture.forecast)
        let encoded = try JSONEncoder.api.encode(APIEnvelope(detail))
        let again = try JSONDecoder.api.decode(APIEnvelope<GymDetail>.self, from: encoded).data

        #expect(again == detail)
    }

    @Test func liveObservedAtAcceptsFractionalSeconds() throws {
        let detail = try Fixture.decode("gym_detail", as: GymDetail.self)
        let observed = try #require(detail.gym.live?.observedAt)

        // 2026-09-09T17:00:00.123456-07:00 == 2026-09-10T00:00:00.123456Z
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-09-10T00:00:00Z"))
        #expect(abs(observed.timeIntervalSince(expected) - 0.123456) < 0.001)
    }

    @Test func rankingsDecodeSortedWithNullableBusyness() throws {
        let rankings = try Fixture.decode("rankings", as: Rankings.self)

        #expect(rankings.locationID.uuidString.lowercased() == "6f1d2c3e-4b5a-4c6d-8e7f-90a1b2c3d4e5")
        #expect(rankings.gyms.map(\.rank) == [1, 2, 3])
        #expect(rankings.best?.slug == "mv-belmont")
        #expect(rankings.best?.isMember == true)
        #expect(rankings.best?.level == .moderate)

        let mosaic = try #require(rankings.gyms.last)
        #expect(mosaic.busyPct == nil)
        #expect(mosaic.level == nil)
        #expect(!mosaic.isOpen)
        #expect(mosaic.score < 0)
    }

    @Test func profileMembershipsAndLocationsDecode() throws {
        let me = try Fixture.decode("me", as: UserProfile.self)
        #expect(me.email == "alex.chen@example.com")
        #expect(me.displayName == "Alex Chen")

        let memberships = try Fixture.decode("memberships", as: [String].self)
        #expect(memberships == ["mv-sf", "mv-belmont", "mv-mountain-view", "mv-santa-clara"])

        let locations = try Fixture.decode("locations", as: [SavedLocation].self)
        let home = try #require(locations.first)
        #expect(home.label == "Home")
        #expect(home.isDefault)
        #expect(home.latitude == 37.4852)
    }

    @Test func newLocationEncodesSnakeCaseBody() throws {
        let body = NewSavedLocation(
            label: "Office", address: nil, latitude: 37.781, longitude: -122.401, isDefault: true
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder.api.encode(body)) as? [String: Any]
        )

        #expect(json["label"] as? String == "Office")
        #expect(json["is_default"] as? Bool == true)
        #expect(json["latitude"] as? Double == 37.781)
        #expect(json.keys.contains("address") == false || json["address"] is NSNull)
    }
}
