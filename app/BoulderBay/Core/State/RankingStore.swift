import Foundation
import Observation

/// The scored list of all sixteen gyms from the current location at the selected
/// moment. Map and Rankings both read it — pins take busyness and travel from here,
/// Rankings takes the order — so it is a store rather than a per-screen service.
///
/// `plannedHour` is the time scrubber: nil means "now"; an hour later today asks the
/// backend for the forecast at that hour.
@MainActor
@Observable
final class RankingStore {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// The scrubber's latest selectable hour, matching the mockup's "10 PM" end stop.
    static let lastPlannableHour = 22

    private(set) var rankings: Rankings?
    private(set) var state: State = .idle
    private var isStale = true

    private let api: any APIClient
    private let locations: LocationStore
    private let now: @Sendable () -> Date
    private var refreshTask: Task<Void, Never>?

    init(api: any APIClient, locations: LocationStore, now: @escaping @Sendable () -> Date = { .now }) {
        self.api = api
        self.locations = locations
        self.now = now
    }

    // MARK: Time selection

    var nowHour: Int { BayArea.hour(now()) }

    /// nil = "now". Setting it to the current hour (or earlier) clears it, as the mockup
    /// does when the slider is dragged back to its start.
    var plannedHour: Int? {
        didSet {
            if let hour = plannedHour, hour <= nowHour { plannedHour = nil }
            if plannedHour != oldValue { isStale = true }
        }
    }

    /// The scrubber's setter: applies the hour and refetches after a short pause, so a
    /// drag doesn't fire a request per step. Both Map and Rankings bind to this.
    func plan(hour: Int?) {
        guard hour != plannedHour else { return }
        plannedHour = hour
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            await refreshIfNeeded()
        }
    }

    /// The hour rankings currently describe.
    var effectiveHour: Int { plannedHour ?? nowHour }
    var isPlanning: Bool { plannedHour != nil }

    /// The `at` parameter for the API — nil for now.
    var plannedDate: Date? {
        plannedHour.map { BayArea.date(today: $0, from: now()) }
    }

    /// The scrubber's range: from now to the last plannable hour. Nil once nothing later
    /// than now can be picked, which hides the time chip.
    var plannableHours: ClosedRange<Int>? {
        nowHour < Self.lastPlannableHour ? nowHour...Self.lastPlannableHour : nil
    }

    // MARK: Data

    var entries: [RankingEntry] { rankings?.gyms ?? [] }
    var best: RankingEntry? { rankings?.best }

    func entry(for slug: String) -> RankingEntry? {
        entries.first { $0.slug == slug }
    }

    /// Forgets everything — sign-out.
    func reset() {
        rankings = nil
        plannedHour = nil
        state = .idle
        isStale = true
    }

    /// Call after anything that changes the score inputs (memberships, location).
    func markStale() {
        isStale = true
    }

    func refreshIfNeeded() async {
        guard isStale || rankings == nil, state != .loading else { return }
        await refresh()
    }

    func refresh() async {
        guard let location = locations.current else {
            rankings = nil
            state = .idle
            return
        }
        state = .loading
        let at = plannedDate
        do {
            let result = try await api.rankings(locationID: location.id, at: at)
            // Ignore a response for a selection that changed while it was in flight.
            guard at == plannedDate else { return }
            rankings = result
            isStale = false
            state = .loaded
        } catch is CancellationError {
            state = rankings == nil ? .idle : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
