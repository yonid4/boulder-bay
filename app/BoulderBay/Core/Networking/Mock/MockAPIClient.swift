import Foundation

/// An in-process stand-in for the backend, serving the seed gyms with synthesized
/// busyness and keeping one account's memberships and locations in memory. Selected by
/// `AppConfig.useMockAPI`; also what previews and most tests run on.
///
/// Time is the real clock unless injected, so "open now" and the live reading follow the
/// day. All sixteen gyms are in America/Los_Angeles, and so is this.
actor MockAPIClient: APIClient {
    /// Everything the mock knows about the signed-in user.
    struct Account: Sendable {
        var profile: UserProfile
        var memberships: Set<String>
        var locations: [SavedLocation]

        /// A returning user: Home in Redwood City and the four Movement gyms.
        static func seeded(profile: UserProfile, now: Date = .now) -> Account {
            Account(
                profile: profile,
                memberships: ["mv-sf", "mv-belmont", "mv-mountain-view", "mv-santa-clara"],
                locations: [
                    SavedLocation(
                        id: UUID(), label: "Home", address: "Redwood City, CA",
                        latitude: 37.4852, longitude: -122.2364, isDefault: true, createdAt: now
                    ),
                ]
            )
        }

        /// A brand-new sign-up: nothing yet, so onboarding runs.
        static func fresh(profile: UserProfile) -> Account {
            Account(profile: profile, memberships: [], locations: [])
        }

        static let previewProfile = UserProfile(
            id: UUID(uuidString: "0b6d1c8a-1e2f-4a3b-9c4d-5e6f7a8b9c0d")!,
            email: "alex.chen@example.com",
            displayName: "Alex Chen"
        )
    }

    private var account: Account
    private let now: @Sendable () -> Date
    private let latency: Duration
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    init(
        account: Account = .seeded(profile: Account.previewProfile),
        now: @escaping @Sendable () -> Date = { .now },
        latency: Duration = .zero
    ) {
        self.account = account
        self.now = now
        self.latency = latency
    }

    /// Swap the account, e.g. when the mock auth service signs a different user in.
    func use(account: Account) {
        self.account = account
    }

    // MARK: Gyms

    func gyms() async throws -> [Gym] {
        try await pause()
        let moment = now()
        return SeedData.gyms.map { Self.summary($0, now: moment) }
    }

    func gym(slug: String) async throws -> GymDetail {
        try await pause()
        guard let seed = SeedData.gym(slug: slug) else { throw APIError.badStatus(404) }
        let today = SeedData.hours(slug: slug, dayOfWeek: dayOfWeek(now()))
        return GymDetail(
            gym: Self.summary(seed, now: now()),
            hours: SeedData.weekHours(slug: slug),
            forecast: today.map { MockBusyness.forecast(slug: slug, hours: $0) } ?? []
        )
    }

    // MARK: Rankings

    func rankings(locationID: UUID, at: Date?) async throws -> Rankings {
        try await pause()
        guard let location = account.locations.first(where: { $0.id == locationID }) else {
            throw APIError.badStatus(404)
        }
        let moment = at ?? now()
        let hour = calendar.component(.hour, from: moment)
        let isNow = at == nil || calendar.isDate(moment, equalTo: now(), toGranularity: .hour)
        let day = dayOfWeek(moment)

        let scored = SeedData.gyms.map { seed -> RankingEntry in
            let hours = SeedData.hours(slug: seed.slug, dayOfWeek: day)
            let isOpen = hours?.contains(ClockTime(hour: hour)) ?? false
            let busy: Int? = if !isOpen {
                nil
            } else if isNow {
                MockBusyness.livePct(slug: seed.slug, hour: hour, hours: hours)
            } else {
                MockBusyness.typicalPct(hour: hour, scale: MockBusyness.scale[seed.slug] ?? 1)
            }
            let miles = MockRanking.miles(
                fromLatitude: location.latitude, longitude: location.longitude,
                toLatitude: seed.latitude, longitude: seed.longitude
            )
            let travel = MockRanking.travelMinutes(miles: miles)
            let member = account.memberships.contains(seed.slug)
            return RankingEntry(
                slug: seed.slug, rank: 0,
                score: MockRanking.score(busyPct: busy, travelMinutes: travel, isMember: member, isOpen: isOpen),
                busyPct: busy, isOpen: isOpen, isMember: member,
                travelMinutes: travel, distanceMiles: (miles * 10).rounded() / 10
            )
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.slug < $1.slug }
        .enumerated()
        .map { index, entry in
            RankingEntry(
                slug: entry.slug, rank: index + 1, score: entry.score, busyPct: entry.busyPct,
                isOpen: entry.isOpen, isMember: entry.isMember,
                travelMinutes: entry.travelMinutes, distanceMiles: entry.distanceMiles
            )
        }
        return Rankings(locationID: locationID, at: moment, gyms: scored)
    }

    // MARK: Me

    func me() async throws -> UserProfile {
        try await pause()
        return account.profile
    }

    func memberships() async throws -> [String] {
        try await pause()
        return orderedMemberships()
    }

    func updateMemberships(_ slugs: [String]) async throws -> [String] {
        try await pause()
        guard slugs.allSatisfy({ SeedData.gym(slug: $0) != nil }) else {
            throw APIError.badStatus(422)
        }
        account.memberships = Set(slugs)
        return orderedMemberships()
    }

    func locations() async throws -> [SavedLocation] {
        try await pause()
        return account.locations
    }

    func createLocation(_ location: NewSavedLocation) async throws -> SavedLocation {
        try await pause()
        guard !account.locations.contains(where: { $0.label == location.label }) else {
            throw APIError.badStatus(409)
        }
        // At most one default: the database's partial unique index, done by hand here.
        if location.isDefault {
            account.locations = account.locations.map {
                SavedLocation(
                    id: $0.id, label: $0.label, address: $0.address,
                    latitude: $0.latitude, longitude: $0.longitude,
                    isDefault: false, createdAt: $0.createdAt
                )
            }
        }
        let saved = SavedLocation(
            id: UUID(), label: location.label, address: location.address,
            latitude: location.latitude, longitude: location.longitude,
            isDefault: location.isDefault, createdAt: now()
        )
        account.locations.append(saved)
        return saved
    }

    func deleteLocation(id: UUID) async throws {
        try await pause()
        guard let index = account.locations.firstIndex(where: { $0.id == id }) else {
            throw APIError.badStatus(404)
        }
        account.locations.remove(at: index)
    }

    // MARK: Helpers

    /// The list shape for one seed gym at `now`. Static so previews can build a `Gym`
    /// without going through the actor.
    nonisolated static func summary(_ seed: SeedData.SeedGym, now moment: Date) -> Gym {
        let today = SeedData.hours(slug: seed.slug, dayOfWeek: BayArea.dayOfWeek(moment))
        let hour = BayArea.hour(moment)
        let live = MockBusyness.livePct(slug: seed.slug, hour: hour, hours: today)
        return Gym(
            slug: seed.slug, name: seed.name, brand: seed.brand, city: seed.city,
            address: seed.address, latitude: seed.latitude, longitude: seed.longitude,
            logoURL: nil,  // nothing serves gym_logos yet; GymLogoView shows initials
            websiteURL: URL(string: seed.websiteURL), waiverURL: URL(string: seed.waiverURL),
            rates: GymRates(
                dayPassCents: seed.dayPassCents, dayPassPeakCents: seed.dayPassPeakCents,
                peakStartsAt: seed.peakStartsAt, monthlyCents: seed.monthlyCents
            ),
            hoursToday: today,
            live: Gym.LiveReading(busyPct: live, observedAt: moment)
        )
    }

    /// Seed order, so lists are stable rather than hash-ordered.
    private func orderedMemberships() -> [String] {
        SeedData.gyms.map(\.slug).filter(account.memberships.contains)
    }

    /// 0 = Sunday, matching the database and `gym_hours`.
    private func dayOfWeek(_ date: Date) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    private func pause() async throws {
        guard latency > .zero else { return }
        try await Task.sleep(for: latency)
    }
}
