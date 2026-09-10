import Foundation
import Observation

/// The membership list: search the sixteen gyms to add, and the gyms you belong to
/// with a Remove pill. Reads `GymStore`, writes `MembershipStore`, and tells
/// `RankingStore` its inputs changed.
@MainActor
@Observable
final class GymsViewModel {
    var query = ""

    private let gyms: GymStore
    private let memberships: MembershipStore
    private let rankings: RankingStore

    init(gyms: GymStore, memberships: MembershipStore, rankings: RankingStore) {
        self.gyms = gyms
        self.memberships = memberships
        self.rankings = rankings
    }

    // MARK: Search

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasQuery: Bool { !trimmedQuery.isEmpty }

    /// Case-insensitive match on name, city or brand — "Benchmark" finds both, "Berkeley"
    /// finds four.
    var results: [Gym] {
        let needle = trimmedQuery.lowercased()
        guard !needle.isEmpty else { return [] }
        return gyms.gyms.filter {
            "\($0.name) \($0.city) \($0.brand.displayName)".lowercased().contains(needle)
        }
    }

    var noResults: Bool { hasQuery && results.isEmpty }

    // MARK: Memberships

    /// In seed order, so the list is stable.
    var memberGyms: [Gym] {
        gyms.gyms.filter { memberships.isMember($0.slug) }
    }

    var memberCountLabel: String {
        switch memberGyms.count {
        case 0: "None yet"
        case 1: "1 gym"
        case let n: "\(n) gyms"
        }
    }

    var errorMessage: String? { memberships.lastError }
    var isLoading: Bool { gyms.state == .loading && gyms.gyms.isEmpty }

    func isMember(_ gym: Gym) -> Bool {
        memberships.isMember(gym.slug)
    }

    // MARK: Actions

    func load() async {
        await gyms.loadIfNeeded()
        await memberships.loadIfNeeded()
    }

    func toggle(_ gym: Gym) async {
        await memberships.toggle(gym.slug)
        rankings.markStale()
    }

    func clearQuery() {
        query = ""
    }
}
