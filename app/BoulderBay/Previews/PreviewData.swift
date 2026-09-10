#if DEBUG
import Foundation

/// Sample values for `#Preview`s, built from the seed data so previews look like the app.
enum PreviewData {
    /// Wednesday 2026-09-09 at 17:00 America/Los_Angeles — the mockup's demo clock.
    static let now: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 9; components.hour = 17
        return BayArea.calendar.date(from: components)!
    }()

    static func gym(_ slug: String) -> Gym {
        MockAPIClient.summary(SeedData.gym(slug: slug)!, now: now)
    }

    static let gyms: [Gym] = SeedData.gyms.map { MockAPIClient.summary($0, now: now) }

    static let belmont = gym("mv-belmont")
    static let dogpatch = gym("dogpatch")
    static let mosaic = gym("mosaic")

    static let home = SavedLocation(
        id: UUID(uuidString: "6f1d2c3e-4b5a-4c6d-8e7f-90a1b2c3d4e5")!,
        label: "Home", address: "Redwood City, CA",
        latitude: 37.4852, longitude: -122.2364, isDefault: true, createdAt: now
    )

    /// A mock client frozen at `now` with the seeded account.
    static func api(fresh: Bool = false) -> MockAPIClient {
        MockAPIClient(
            account: fresh ? .fresh(profile: .init(id: AuthUser.preview.id, email: AuthUser.preview.email, displayName: AuthUser.preview.displayName))
                           : .seeded(profile: MockAPIClient.Account.previewProfile, now: now),
            now: { now }
        )
    }
}
#endif
