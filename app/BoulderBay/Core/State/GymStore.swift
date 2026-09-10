import Foundation
import Observation

/// The sixteen gyms with today's hours and the latest live reading, shared by every
/// screen. Refreshed on demand; nothing polls in v1.
@MainActor
@Observable
final class GymStore {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var gyms: [Gym] = []
    private(set) var state: State = .idle

    private let api: any APIClient

    init(api: any APIClient) {
        self.api = api
    }

    var bySlug: [String: Gym] {
        Dictionary(uniqueKeysWithValues: gyms.map { ($0.slug, $0) })
    }

    func gym(slug: String) -> Gym? {
        gyms.first { $0.slug == slug }
    }

    /// Fetches the list, replacing what's there. Safe to call repeatedly.
    func load() async {
        state = .loading
        do {
            gyms = try await api.gyms()
            state = .loaded
        } catch is CancellationError {
            state = gyms.isEmpty ? .idle : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Fetches only if nothing has been loaded yet.
    func loadIfNeeded() async {
        guard gyms.isEmpty, state != .loading else { return }
        await load()
    }
}
