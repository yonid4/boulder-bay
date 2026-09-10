import Foundation
import Testing

@testable import BoulderBay

struct MockAPIClientTests {
    /// Wednesday 2026-09-09 at 17:00 America/Los_Angeles.
    static let wednesday5pm: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 9; components.hour = 17
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar.date(from: components)!
    }()

    /// Same day at 03:00 — every gym is closed.
    static let wednesday3am = wednesday5pm.addingTimeInterval(-14 * 3600)

    static let migrationSlugs = [
        "mission", "dogpatch", "hyperion", "gwpc", "pipe", "ironworks", "the-oaks",
        "studio", "mv-sf", "mv-belmont", "mv-mountain-view", "mv-santa-clara",
        "bm-sf", "bm-berkeley", "the-peak", "mosaic",
    ]

    func client(account: MockAPIClient.Account? = nil, now: Date = wednesday5pm) -> MockAPIClient {
        MockAPIClient(
            account: account ?? .seeded(profile: .init(id: UUID(), email: "t@example.com", displayName: "T")),
            now: { now }
        )
    }

    // MARK: Seed fidelity

    @Test func seedMatchesTheMigration() {
        #expect(SeedData.gyms.map(\.slug) == Self.migrationSlugs)
        #expect(SeedData.gyms.filter { $0.brand == .touchstone }.count == 8)
        #expect(SeedData.gyms.filter { $0.brand == .movement }.count == 4)
        #expect(SeedData.gyms.filter { $0.brand == .benchmark }.count == 2)
        #expect(SeedData.gyms.filter { $0.brand == .independent }.count == 2)
        #expect(Set(SeedData.gyms.map(\.logoKey)).count == 12)

        let rows = SeedData.gyms.flatMap { SeedData.weekHours(slug: $0.slug) }
        #expect(rows.count == 112)
        #expect(rows.reduce(0) { $0 + $1.closesAt.hour - $1.opensAt.hour } == 1450)
        #expect(SeedData.hours(slug: "dogpatch", dayOfWeek: 2)?.closesAt == ClockTime(hour: 23))
        #expect(SeedData.hours(slug: "mosaic", dayOfWeek: 1)?.opensAt == ClockTime(hour: 13))
        #expect(SeedData.gym(slug: "studio")?.dayPassCents == 2500)
    }

    @Test func everyLogoKeyResolvesToABundledFile() {
        for key in Set(SeedData.gyms.map(\.logoKey)) {
            let url = SeedData.logoURL(key: key)
            #expect(url.map { FileManager.default.fileExists(atPath: $0.path()) } == true, "\(key)")
        }
        // Brand-level marks are shared, mirroring gyms.logo_id in the seed.
        let movement = SeedData.gyms.filter { $0.brand == .movement }.map(\.logoKey)
        #expect(Set(movement) == ["movement"])
        #expect(Set(SeedData.gyms.filter { $0.brand == .benchmark }.map(\.logoKey)) == ["benchmark"])
    }

    // MARK: Gyms

    @Test func gymsCarryTodaysHoursAndALiveReadingWhenOpen() async throws {
        let gyms = try await client().gyms()

        #expect(gyms.count == 16)
        let mission = try #require(gyms.first { $0.slug == "mission" })
        #expect(mission.hoursToday == HoursRange(opensAt: ClockTime(hour: 6), closesAt: ClockTime(hour: 22)))
        #expect(mission.live?.busyPct != nil)
        #expect(mission.logoURL?.lastPathComponent == "mission.png")
        #expect(mission.rates.hasPeakTier)
    }

    @Test func closedGymsHaveNoLiveReading() async throws {
        let gyms = try await client(now: Self.wednesday3am).gyms()
        #expect(gyms.allSatisfy { $0.live?.busyPct == nil })
    }

    @Test func detailHasSevenDaysAndAForecastPerOpenHour() async throws {
        let detail = try await client().gym(slug: "mv-belmont")

        #expect(detail.hours.count == 7)
        #expect(detail.forecast.map(\.hour) == Array(6..<23))
        #expect(detail.forecast.allSatisfy { (0...100).contains($0.busyPct) })
        let peak = try #require(detail.forecast.max { $0.busyPct < $1.busyPct })
        #expect((17...19).contains(peak.hour))
    }

    @Test func unknownSlugIs404() async {
        await #expect(throws: APIError.badStatus(404)) {
            try await client().gym(slug: "bridges")
        }
    }

    // MARK: Rankings

    @Test func rankingsAreSortedAndFollowTheFormula() async throws {
        let api = client()
        let home = try #require(try await api.locations().first)

        let rankings = try await api.rankings(locationID: home.id, at: nil)

        #expect(rankings.gyms.count == 16)
        #expect(rankings.gyms.map(\.rank) == Array(1...16))
        #expect(rankings.gyms.map(\.score) == rankings.gyms.map(\.score).sorted(by: >))
        for entry in rankings.gyms {
            let expected = MockRanking.score(
                busyPct: entry.busyPct, travelMinutes: entry.travelMinutes,
                isMember: entry.isMember, isOpen: entry.isOpen
            )
            #expect(entry.score == expected)
        }
        #expect(rankings.gyms.filter(\.isMember).map(\.slug).sorted()
            == ["mv-belmont", "mv-mountain-view", "mv-santa-clara", "mv-sf"])
        // Hyperion is a few miles from the Redwood City home.
        let hyperion = try #require(rankings.gyms.first { $0.slug == "hyperion" })
        #expect(hyperion.distanceMiles < 3)
        let seed = try #require(SeedData.gym(slug: "hyperion"))
        let miles = MockRanking.miles(
            fromLatitude: home.latitude, longitude: home.longitude,
            toLatitude: seed.latitude, longitude: seed.longitude
        )
        #expect(hyperion.travelMinutes == MockRanking.travelMinutes(miles: miles))
    }

    @Test func closedGymsArePenalisedAndHaveNoBusyness() async throws {
        let api = client()
        let home = try #require(try await api.locations().first)

        let rankings = try await api.rankings(locationID: home.id, at: Self.wednesday3am)

        #expect(rankings.gyms.allSatisfy { !$0.isOpen && $0.busyPct == nil })
        #expect(rankings.gyms.allSatisfy { $0.score < 60 })
    }

    @Test func forecastHourUsesTheCurveNotTheLiveReading() async throws {
        let api = client()
        let home = try #require(try await api.locations().first)
        let at9pm = Self.wednesday5pm.addingTimeInterval(4 * 3600)

        let later = try await api.rankings(locationID: home.id, at: at9pm)
        let mission = try #require(later.gyms.first { $0.slug == "mission" })

        #expect(mission.busyPct == MockBusyness.typicalPct(hour: 21, scale: MockBusyness.scale["mission"]!))
    }

    @Test func unknownLocationIs404() async {
        await #expect(throws: APIError.badStatus(404)) {
            try await client().rankings(locationID: UUID(), at: nil)
        }
    }

    // MARK: Me

    @Test func seededAccountHasHomeAndTheMovementGyms() async throws {
        let api = client()
        #expect(try await api.memberships() == ["mv-sf", "mv-belmont", "mv-mountain-view", "mv-santa-clara"])
        let locations = try await api.locations()
        #expect(locations.map(\.label) == ["Home"])
        #expect(locations.first?.isDefault == true)
    }

    @Test func freshAccountStartsEmpty() async throws {
        let profile = UserProfile(id: UUID(), email: "new@example.com", displayName: "New")
        let api = client(account: .fresh(profile: profile))
        #expect(try await api.me() == profile)
        #expect(try await api.memberships().isEmpty)
        #expect(try await api.locations().isEmpty)
    }

    @Test func membershipsReplaceTheWholeSetInSeedOrder() async throws {
        let api = client()
        let stored = try await api.updateMemberships(["mosaic", "mission"])
        #expect(stored == ["mission", "mosaic"])
        #expect(try await api.memberships() == ["mission", "mosaic"])

        await #expect(throws: APIError.badStatus(422)) {
            try await api.updateMemberships(["bridges"])
        }
    }

    @Test func locationsCanBeCreatedAndDeleted() async throws {
        let api = client(account: .fresh(profile: .init(id: UUID(), email: "n@x.io", displayName: nil)))
        let created = try await api.createLocation(
            NewSavedLocation(label: "Home", address: nil, latitude: 37.5, longitude: -122.3, isDefault: true)
        )
        #expect(created.isDefault)
        #expect(try await api.locations() == [created])

        let office = try await api.createLocation(
            NewSavedLocation(label: "Office", address: "SoMa", latitude: 37.78, longitude: -122.4, isDefault: true)
        )
        let after = try await api.locations()
        #expect(after.filter(\.isDefault).map(\.label) == ["Office"])

        await #expect(throws: APIError.badStatus(409)) {
            try await api.createLocation(
                NewSavedLocation(label: "Office", address: nil, latitude: 0, longitude: 0, isDefault: false)
            )
        }

        try await api.deleteLocation(id: office.id)
        #expect(try await api.locations().map(\.label) == ["Home"])
        await #expect(throws: APIError.badStatus(404)) {
            try await api.deleteLocation(id: office.id)
        }
    }
}
