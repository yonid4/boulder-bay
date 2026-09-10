import Foundation
import Testing

@testable import BoulderBay

/// Wednesday 2026-09-09 at 17:00 America/Los_Angeles, shared by the store tests.
let wednesday5pm: Date = {
    var components = DateComponents()
    components.year = 2026; components.month = 9; components.day = 9; components.hour = 17
    return BayArea.calendar.date(from: components)!
}()

private func freshProfile() -> UserProfile {
    UserProfile(id: UUID(), email: "new@example.com", displayName: nil)
}

@MainActor
struct GymStoreTests {
    @Test func loadPopulatesAllSixteen() async {
        let api = SpyAPIClient()
        let store = GymStore(api: api)
        #expect(store.state == .idle)

        await store.load()

        #expect(store.state == .loaded)
        #expect(store.gyms.count == 16)
        #expect(store.gym(slug: "mosaic")?.city == "Berkeley")
        #expect(store.bySlug["mission"]?.brand == .touchstone)
    }

    @Test func loadIfNeededFetchesOnce() async {
        let api = SpyAPIClient()
        let store = GymStore(api: api)

        await store.loadIfNeeded()
        await store.loadIfNeeded()

        #expect(api.calls == [.gyms])
    }

    @Test func failureIsSurfacedAndRetryable() async {
        let api = SpyAPIClient()
        api.failNext(with: .badStatus(503))
        let store = GymStore(api: api)

        await store.load()
        #expect(store.state == .failed(APIError.badStatus(503).localizedDescription))
        #expect(store.gyms.isEmpty)

        await store.load()
        #expect(store.state == .loaded)
    }
}

@MainActor
struct LocationStoreTests {
    @Test func currentIsTheDefault() async {
        let store = LocationStore(api: SpyAPIClient())
        #expect(!store.hasLoaded)

        await store.load()

        #expect(store.hasLoaded)
        #expect(store.current?.label == "Home")
    }

    @Test func firstCreatedLocationBecomesTheDefault() async throws {
        let api = SpyAPIClient(inner: MockAPIClient(account: .fresh(profile: freshProfile())))
        let store = LocationStore(api: api)
        await store.load()
        #expect(store.current == nil)

        let home = try await store.create(label: "Home", address: "Redwood City", latitude: 37.48, longitude: -122.23)
        #expect(home.isDefault)
        #expect(store.current == home)

        let office = try await store.create(label: "Office", address: nil, latitude: 37.78, longitude: -122.4)
        #expect(!office.isDefault)
        #expect(store.current == home)
        #expect(api.calls.contains(.createLocation("Office")))
    }

    @Test func refusesToDeleteTheLastLocation() async throws {
        let api = SpyAPIClient()
        let store = LocationStore(api: api)
        await store.load()
        let home = try #require(store.current)

        await #expect(throws: LocationStoreError.cannotDeleteLastLocation) {
            try await store.delete(id: home.id)
        }
        #expect(store.locations.count == 1)
        #expect(!api.calls.contains(.deleteLocation(home.id)))

        try await store.create(label: "Office", address: nil, latitude: 37.78, longitude: -122.4)
        try await store.delete(id: home.id)
        #expect(store.locations.map(\.label) == ["Office"])
    }
}

@MainActor
struct MembershipStoreTests {
    @Test func loadReadsTheSeededSet() async {
        let store = MembershipStore(api: SpyAPIClient())
        await store.load()
        #expect(store.slugs == ["mv-sf", "mv-belmont", "mv-mountain-view", "mv-santa-clara"])
        #expect(store.isMember("mv-sf"))
        #expect(!store.isMember("mosaic"))
    }

    @Test func togglePutsTheWholeSet() async {
        let api = SpyAPIClient()
        let store = MembershipStore(api: api)
        await store.load()

        await store.toggle("mosaic")
        #expect(store.isMember("mosaic"))
        #expect(api.calls.last == .updateMemberships(["mosaic", "mv-belmont", "mv-mountain-view", "mv-santa-clara", "mv-sf"]))

        await store.toggle("mv-sf")
        #expect(!store.isMember("mv-sf"))
        #expect(api.calls.last == .updateMemberships(["mosaic", "mv-belmont", "mv-mountain-view", "mv-santa-clara"]))
    }

    @Test func failedToggleRollsBack() async {
        let api = SpyAPIClient()
        let store = MembershipStore(api: api)
        await store.load()

        api.failNext()
        await store.toggle("mosaic")

        #expect(!store.isMember("mosaic"))
        #expect(store.lastError != nil)
        #expect(store.slugs.count == 4)
    }
}

@MainActor
struct RankingStoreTests {
    private func makeStores(now: Date = wednesday5pm) async -> (SpyAPIClient, LocationStore, RankingStore) {
        let api = SpyAPIClient(inner: MockAPIClient(now: { now }))
        let locations = LocationStore(api: api)
        await locations.load()
        return (api, locations, RankingStore(api: api, locations: locations, now: { now }))
    }

    @Test func refreshScoresFromTheCurrentLocationNow() async throws {
        let (api, locations, store) = await makeStores()

        await store.refreshIfNeeded()

        #expect(store.state == .loaded)
        #expect(store.entries.count == 16)
        #expect(store.best?.rank == 1)
        #expect(store.entry(for: "mosaic") != nil)
        #expect(api.calls.last == .rankings(try #require(locations.current?.id), nil))
        #expect(store.nowHour == 17)
        #expect(!store.isPlanning)
        #expect(store.effectiveHour == 17)
    }

    @Test func plannedHourAsksForTheForecastAndNormalises() async throws {
        let (api, _, store) = await makeStores()
        await store.refreshIfNeeded()

        store.plannedHour = 20
        #expect(store.isPlanning)
        #expect(store.effectiveHour == 20)
        await store.refreshIfNeeded()
        let at = try #require(store.plannedDate)
        #expect(BayArea.hour(at) == 20)
        #expect(api.calls.last == .rankings(try #require(store.rankings?.locationID), at))

        // Dragging back to "now" clears the plan.
        store.plannedHour = 17
        #expect(store.plannedHour == nil)
        #expect(!store.isPlanning)
        #expect(store.plannableHours == 17...22)
    }

    @Test func refreshIfNeededOnlyRefetchesWhenStale() async {
        let (api, _, store) = await makeStores()

        await store.refreshIfNeeded()
        await store.refreshIfNeeded()
        let fetches = { api.calls.filter { if case .rankings = $0 { true } else { false } }.count }
        #expect(fetches() == 1)

        store.markStale()
        await store.refreshIfNeeded()
        #expect(fetches() == 2)
    }

    @Test func noLocationMeansNoRankings() async {
        let api = SpyAPIClient(inner: MockAPIClient(account: .fresh(profile: freshProfile())))
        let locations = LocationStore(api: api)
        await locations.load()
        let store = RankingStore(api: api, locations: locations)

        await store.refresh()

        #expect(store.rankings == nil)
        #expect(store.state == .idle)
    }

    @Test func lateAtNightNothingIsPlannable() async {
        let (_, _, store) = await makeStores(now: wednesday5pm.addingTimeInterval(6 * 3600))
        #expect(store.nowHour == 23)
        #expect(store.plannableHours == nil)
    }
}

struct FormatTests {
    @Test func hoursSpellLikeTheMockup() {
        #expect(Format.hour(0) == "12 AM")
        #expect(Format.hour(6) == "6 AM")
        #expect(Format.hour(12) == "12 PM")
        #expect(Format.hour(17) == "5 PM")
        #expect(Format.window(startingAt: 19) == "7 PM – 8 PM")
        #expect(Format.hoursRange(HoursRange(opensAt: ClockTime(hour: 6), closesAt: ClockTime(hour: 22))) == "6 AM – 10 PM")
        #expect(Format.clockTime(ClockTime(hour: 6, minute: 30)) == "6:30 AM")
    }

    @Test func moneyDistanceAndStatus() {
        #expect(Format.dollars(cents: 3000) == "$30")
        #expect(Format.dollars(cents: 3350) == "$33.50")
        #expect(Format.miles(8.34) == "8.3 mi")
        #expect(Format.minutes(12) == "12 min")
        let hours = HoursRange(opensAt: ClockTime(hour: 6), closesAt: ClockTime(hour: 22))
        #expect(Format.openStatus(hoursToday: hours, at: 17) == "Open until 10 PM")
        #expect(Format.openStatus(hoursToday: hours, at: 22) == "Closed")
        #expect(Format.openStatus(hoursToday: nil, at: 12) == "Closed")
    }

    @Test func bayAreaCalendarIsPacific() {
        #expect(BayArea.dayOfWeek(wednesday5pm) == 3)
        #expect(BayArea.hour(wednesday5pm) == 17)
        #expect(BayArea.hour(BayArea.date(today: 20, from: wednesday5pm)) == 20)
    }
}
