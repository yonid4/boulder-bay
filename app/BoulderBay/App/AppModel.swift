import Foundation
import Observation

/// State every screen shares: the signed-in profile, their places and gym memberships, the
/// hour the Map and Rankings resolve busyness for, and the gym list. Created once in
/// `AppContainer`; `bootstrap()` fills it after sign-in, except the gym list, which screens
/// load when they need it.
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
    /// Every gym, as last loaded for one hour by `loadGyms()`, so its busyness may be for
    /// another hour than `selectedHour`. Kept through a failed reload, and in memory until a
    /// poll ping, a return after `backgroundRefreshInterval` or a restart replaces it.
    private(set) var gyms: [Gym] = []
    private(set) var gymsState: LoadState = .idle
    /// Bumped when a poll tick has landed new busyness and the selected hour is now, or the app
    /// returns after `backgroundRefreshInterval`. Screens fetching their own data refetch when
    /// it changes; `gyms` is already refreshed by the same events.
    private(set) var liveRefreshCount = 0

    /// How long the app has to be in the background before its data counts as out of date.
    static let backgroundRefreshInterval: TimeInterval = 5 * 60

    /// The one gym load in flight, and the hour it is fetching.
    private var gymsLoad: (hour: Int, task: Task<Void, Never>)?
    /// The hour `gyms` was loaded for.
    private var gymsHour: Int?
    /// When the app last went to the background, until it comes back.
    private var backgroundedAt: Date?
    /// Identifies the account `bootstrap()` is loading for: a load started before a reset
    /// mustn't publish into the next account.
    private var accountLoad = 0
    /// The newest `reloadLocations()` request. An older one's answer may predate a write.
    private var locationsRequest = 0

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
    /// again as a retry. A failure keeps none of the three, so no stale account shows. The gym
    /// list carries a per-user `isMember`, so it is cleared too, and any load in flight dropped.
    func bootstrap() async {
        guard state != .loading else { return }
        clearAccountData()
        state = .loading
        let load = accountLoad

        async let profile = apiClient.me()
        async let locations = apiClient.locations()
        async let memberships = apiClient.memberships()
        do {
            let (loadedProfile, loadedLocations, loadedMemberships) = try await (
                profile, locations, memberships
            )
            guard load == accountLoad else { return }
            self.profile = loadedProfile
            self.memberships = Set(loadedMemberships)
            setLocations(loadedLocations)
            state = .loaded
        } catch {
            guard load == accountLoad else { return }
            state = .failed(APIError.message(for: error))
        }
    }

    /// Forgets the account when the session ends, so the next sign-in starts from the loading
    /// gate at the current hour and never mounts the shell on the previous account's data.
    func reset() {
        clearAccountData()
        state = .idle
        pendingMemberships = []
        membershipError = nil
        backgroundedAt = nil
        selectedHour = calendar.component(.hour, from: now())
    }

    private func clearAccountData() {
        accountLoad += 1
        locationsRequest += 1
        profile = nil
        memberships = []
        setLocations([])
        gymsLoad?.task.cancel()
        gymsLoad = nil
        gyms = []
        gymsHour = nil
        gymsState = .idle
    }

    // MARK: Gyms

    /// Fetches the gyms for `selectedHour`. A load already fetching that hour is joined, not
    /// repeated; one fetching another hour is dropped. The load outlives the caller's task, so
    /// leaving a screen mid-load doesn't fail it for the next screen.
    func loadGyms() async {
        let hour = selectedHour
        if let gymsLoad {
            guard gymsLoad.hour != hour else { return await gymsLoad.task.value }
            gymsLoad.task.cancel()
        }
        gymsState = .loading
        let task = Task { await fetchGyms(hour: hour) }
        gymsLoad = (hour, task)
        await task.value
    }

    /// For a screen that needs the list but not any particular hour: no request if it's loaded.
    func loadGymsIfNeeded() async {
        guard gyms.isEmpty, gymsState != .loaded else { return }
        await loadGyms()
    }

    /// Whether `gyms` is the loaded list for `selectedHour`, so a screen showing that hour's
    /// busyness has nothing to fetch.
    var hasGymsForSelectedHour: Bool {
        gymsState == .loaded && gymsHour == selectedHour
    }

    /// Whether any screen has asked for the list, so it's worth refreshing.
    private var hasRequestedGyms: Bool {
        gymsState != .idle || !gyms.isEmpty
    }

    private func fetchGyms(hour: Int) async {
        do {
            let gyms = try await apiClient.gyms(at: date(forHour: hour))
            guard finishGymsLoad(hour: hour) else { return }
            self.gyms = gyms
            gymsHour = hour
            gymsState = .loaded
        } catch {
            guard finishGymsLoad(hour: hour) else { return }
            gymsState = .failed(APIError.message(for: error))
        }
    }

    /// Ends the load, returning whether its result still counts: not if a newer load or
    /// `bootstrap()` dropped it, nor if the hour moved while it was in flight.
    private func finishGymsLoad(hour: Int) -> Bool {
        guard !Task.isCancelled else { return false }
        gymsLoad = nil
        guard hour == selectedHour else {
            gymsState = .idle
            return false
        }
        return true
    }

    // MARK: Locations

    /// Picks the place the map and rankings work from. An id that isn't one of
    /// `locations` is ignored.
    func selectLocation(id: UUID) {
        guard locations.contains(where: { $0.id == id }) else { return }
        selectedLocationID = id
    }

    /// Refetches the places, e.g. after a write that moved the default on the server.
    /// On failure the old list stays and the error is rethrown for the caller to show. Only the
    /// newest request counts: an older answer may predate a write, so it is dropped, success or
    /// failure, and this returns false.
    @discardableResult
    func reloadLocations() async throws -> Bool {
        locationsRequest += 1
        let request = locationsRequest
        do {
            let locations = try await apiClient.locations()
            guard request == locationsRequest else { return false }
            setLocations(locations)
            return true
        } catch {
            guard request == locationsRequest else { return false }
            throw error
        }
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

    /// Whether the user belongs to `gym`, from `memberships` rather than `gym.isMember`: the
    /// set changes the moment a membership is toggled, while the flag is only as fresh as the
    /// last load.
    func isMember(_ gym: Gym) -> Bool {
        memberships.contains(gym.slug)
    }

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
            await refresh()
        }
    }

    /// Notes that the app left the foreground. Only `.background` counts, not `.inactive`,
    /// which also covers a passing system sheet or Control Center.
    func appDidEnterBackground() {
        backgroundedAt = now()
    }

    /// After `backgroundRefreshInterval` or longer away, goes back to the current hour and
    /// refreshes. A shorter absence keeps the chosen hour and what's loaded.
    func appDidBecomeActive() async {
        guard let backgroundedAt else { return }
        self.backgroundedAt = nil
        guard now().timeIntervalSince(backgroundedAt) >= Self.backgroundRefreshInterval else {
            return
        }
        selectedHour = calendar.component(.hour, from: now())
        await refresh()
    }

    /// Replaces the gym list here rather than leaving it to whichever screen is showing, so a
    /// screen that isn't mounted right now doesn't come back to an out-of-date list.
    private func refresh() async {
        liveRefreshCount += 1
        if hasRequestedGyms {
            await loadGyms()
        }
    }
}
