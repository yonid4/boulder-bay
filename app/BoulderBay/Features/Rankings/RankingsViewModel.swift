import Foundation
import Observation

/// One row of the Rankings list: the ranking entry joined with its gym.
struct RankedGym: Identifiable, Hashable {
    let entry: RankingEntry
    let gym: Gym

    var id: String { gym.slug }
    var rank: Int { entry.rank }
}

/// Joins `RankingStore` with `GymStore` for the Rankings screen: the best pick, the
/// seven runners-up, and the copy that changes with the scrubber.
@MainActor
@Observable
final class RankingsViewModel {
    /// The best pick plus seven more, as the mockup lays out.
    static let rowCount = 8

    var isTimeOpen = false

    private let gyms: GymStore
    private let rankings: RankingStore
    private let memberships: MembershipStore
    private let locations: LocationStore

    init(gyms: GymStore, rankings: RankingStore, memberships: MembershipStore, locations: LocationStore) {
        self.gyms = gyms
        self.rankings = rankings
        self.memberships = memberships
        self.locations = locations
    }

    // MARK: Data

    var ranked: [RankedGym] {
        let bySlug = gyms.bySlug
        return rankings.entries.compactMap { entry in
            bySlug[entry.slug].map { RankedGym(entry: entry, gym: $0) }
        }
    }

    var best: RankedGym? { ranked.first }
    var rest: [RankedGym] { Array(ranked.dropFirst().prefix(Self.rowCount - 1)) }

    var isLoading: Bool { rankings.state == .loading && rankings.rankings == nil }
    var errorMessage: String? {
        if case .failed(let message) = rankings.state, rankings.rankings == nil { return message }
        return nil
    }

    // MARK: Copy

    var subtitle: String {
        rankings.isPlanning
            ? "Forecast for \(Format.hour(rankings.effectiveHour))"
            : "Live, \(Format.hour(rankings.nowHour))"
    }

    var bestPickLabel: String {
        rankings.isPlanning ? "Best pick for \(Format.hour(rankings.effectiveHour))" : "Best pick right now"
    }

    var timeChipLabel: String {
        rankings.isPlanning ? Format.hour(rankings.effectiveHour) : "Now"
    }

    /// "Your gym, and it's quiet right now" / "Quiet at 6 PM and close to Home".
    func whyLine(for ranked: RankedGym) -> String {
        let when = rankings.isPlanning ? "at \(Format.hour(rankings.effectiveHour))" : "right now"
        let level = ranked.entry.level?.label.lowercased()
        let locationLabel = locations.current?.label ?? "you"
        if ranked.entry.isMember {
            guard let level else { return "Your gym, but it's closed \(when)" }
            return rankings.isPlanning
                ? "Your gym, and it should be \(level) \(when)"
                : "Your gym, and it's \(level) \(when)"
        }
        guard let level else { return "Closed \(when), but close to \(locationLabel)" }
        return "\(level.capitalized) \(when) and close to \(locationLabel)"
    }

    var plannableHours: ClosedRange<Int>? { rankings.plannableHours }

    var plannedHour: Int? {
        get { rankings.plannedHour }
        set { rankings.plan(hour: newValue) }
    }

    // MARK: Actions

    func load() async {
        await gyms.loadIfNeeded()
        await memberships.loadIfNeeded()
        await rankings.refreshIfNeeded()
    }

    func retry() async {
        await rankings.refresh()
    }

    func toggleTime() {
        isTimeOpen.toggle()
    }

    func closeTime() {
        isTimeOpen = false
    }
}
