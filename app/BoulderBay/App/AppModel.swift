import Foundation
import Observation

/// State every screen shares: the signed-in profile, their places and gym memberships, and
/// the hour the Map and Rankings resolve busyness for. Created once in `AppContainer`;
/// `bootstrap()` fills it after sign-in.
@MainActor
@Observable
final class AppModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Where `bootstrap()` is. Gate on `.loaded` before reading `locations`: an empty list
    /// only means "no places yet" once the load has succeeded.
    private(set) var state: LoadState = .idle
    private(set) var profile: UserProfile?
    /// In creation order, as the API returns them.
    private(set) var locations: [SavedLocation] = []
    /// Starts as the default place, and falls back to it when the selected one goes away.
    private(set) var selectedLocationID: UUID?
    /// Slugs of the gyms the user belongs to. The source of truth for membership in the UI;
    /// `Gym.isMember` is only as fresh as the last gym load.
    private(set) var memberships: Set<String> = []
    /// Slugs with a membership change in flight. Toggling one of them again is ignored.
    private(set) var pendingMemberships: Set<String> = []
    /// Set when a membership change fails and is rolled back. The UI clears it once shown.
    var membershipError: String?
    /// The hour of today (0–23) the Map and Rankings resolve busyness for. Defaults to the
    /// current hour with the minutes dropped, so 5:59 PM starts at 17.
    var selectedHour: Int
    /// Bumped when a poll tick has landed new busyness and the selected hour is now. Screens
    /// showing live data refetch when it changes.
    private(set) var liveRefreshCount = 0

    private let apiClient: APIClient
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let pollPings: @Sendable () -> AsyncStream<Void>
    private let refreshDelay: @Sendable () -> Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    /// - Parameters:
    ///   - pollPings: a ping per finished poll tick (`PollListener.pings` in the app).
    ///   - refreshDelay: how long to wait after a ping before refreshing, random by default so
    ///     every open app doesn't hit the server at once.
    init(
        apiClient: APIClient,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
        pollPings: @escaping @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } },
        refreshDelay: @escaping @Sendable () -> Duration = {
            .milliseconds(Int.random(in: 0...20_000))
        },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.apiClient = apiClient
        self.calendar = calendar
        self.now = now
        self.pollPings = pollPings
        self.refreshDelay = refreshDelay
        self.sleep = sleep
        selectedHour = calendar.component(.hour, from: now())
    }

    var selectedLocation: SavedLocation? {
        locations.first { $0.id == selectedLocationID }
    }

    // MARK: Bootstrap

    /// Loads the profile, places and memberships concurrently. Runs once after sign-in, and
    /// again as a retry. A failure keeps none of the three, so no stale account shows.
    func bootstrap() async {
        guard state != .loading else { return }
        state = .loading
        profile = nil
        memberships = []
        setLocations([])

        async let profile = apiClient.me()
        async let locations = apiClient.locations()
        async let memberships = apiClient.memberships()
        do {
            let (loadedProfile, loadedLocations, loadedMemberships) = try await (
                profile, locations, memberships
            )
            self.profile = loadedProfile
            self.memberships = Set(loadedMemberships)
            setLocations(loadedLocations)
            state = .loaded
        } catch {
            state = .failed(APIError.message(for: error))
        }
    }

    // MARK: Locations

    /// Picks the place the map and rankings work from. An id that isn't one of
    /// `locations` is ignored.
    func selectLocation(id: UUID) {
        guard locations.contains(where: { $0.id == id }) else { return }
        selectedLocationID = id
    }

    /// Refetches the places, e.g. after a write that moved the default on the server.
    /// On failure the old list stays and the error is rethrown for the caller to show.
    func reloadLocations() async throws {
        setLocations(try await apiClient.locations())
    }

    /// Keeps the selection while that place exists; otherwise falls back to the default
    /// place, then to the first.
    private func setLocations(_ newLocations: [SavedLocation]) {
        locations = newLocations
        if selectedLocation == nil {
            selectedLocationID = (newLocations.first(where: \.isDefault) ?? newLocations.first)?.id
        }
    }

    // MARK: Memberships

    /// Joins or leaves a gym optimistically: the set flips at once, and a failed request
    /// flips it back and sets `membershipError`.
    func toggleMembership(gymSlug: String) async {
        guard !pendingMemberships.contains(gymSlug) else { return }
        pendingMemberships.insert(gymSlug)
        defer { pendingMemberships.remove(gymSlug) }

        let wasMember = memberships.contains(gymSlug)
        if wasMember {
            memberships.remove(gymSlug)
        } else {
            memberships.insert(gymSlug)
        }

        do {
            if wasMember {
                try await apiClient.removeMembership(gymSlug: gymSlug)
            } else {
                try await apiClient.addMembership(gymSlug: gymSlug)
            }
        } catch {
            if wasMember {
                memberships.insert(gymSlug)
            } else {
                memberships.remove(gymSlug)
            }
            membershipError = APIError.message(for: error)
        }
    }

    // MARK: Hour

    /// Whether `selectedHour` is the current hour, i.e. the screens show live busyness.
    var isSelectedHourNow: Bool {
        selectedHour == calendar.component(.hour, from: now())
    }

    /// Today at `hour`:00 in the device's timezone.
    func date(forHour hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now()) ?? now()
    }

    // MARK: Live refresh

    /// Turns each poll ping into a `liveRefreshCount` bump, after a random delay, while the
    /// selected hour is now. Runs until cancelled, so tie it to the signed-in UI with `.task`.
    func listenForPolls() async {
        for await _ in pollPings() {
            guard isSelectedHourNow else { continue }
            do {
                try await sleep(refreshDelay())
            } catch {
                return
            }
            // The user may have moved to another hour while this waited.
            guard !Task.isCancelled, isSelectedHourNow else { continue }
            liveRefreshCount += 1
        }
    }
}
