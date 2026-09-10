import Foundation
import Observation

/// Which gyms the user belongs to. Drives the +15 ranking boost, the clay pin ring, and
/// the Member badge. Writes are optimistic: the toggle shows immediately and rolls back
/// if `PUT /api/me/memberships` fails.
@MainActor
@Observable
final class MembershipStore {
    private(set) var slugs: Set<String> = []
    private(set) var hasLoaded = false
    /// The last write that failed, for the Gyms screen to surface.
    private(set) var lastError: String?

    private let api: any APIClient

    init(api: any APIClient) {
        self.api = api
    }

    func isMember(_ slug: String) -> Bool {
        slugs.contains(slug)
    }

    /// Forgets everything — sign-out.
    func reset() {
        slugs = []
        hasLoaded = false
        lastError = nil
    }

    func load() async {
        do {
            slugs = Set(try await api.memberships())
            hasLoaded = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    /// Adds or removes one gym, replacing the whole set on the server.
    func toggle(_ slug: String) async {
        let previous = slugs
        if slugs.contains(slug) { slugs.remove(slug) } else { slugs.insert(slug) }
        lastError = nil
        do {
            slugs = Set(try await api.updateMemberships(Array(slugs)))
        } catch {
            slugs = previous
            lastError = error.localizedDescription
        }
    }
}
