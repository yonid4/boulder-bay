import Foundation
import Observation

enum LocationStoreError: Error, Equatable {
    /// v1 keeps at least one saved location; there is no screen without one.
    case cannotDeleteLastLocation
}

/// The user's saved locations. v1 creates exactly one in onboarding and never edits it,
/// but the store is list-shaped with a default so v2's Settings page needs no reshaping.
/// Rankings and travel times are always relative to `current`.
@MainActor
@Observable
final class LocationStore {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var locations: [SavedLocation] = []
    private(set) var state: State = .idle

    private let api: any APIClient

    init(api: any APIClient) {
        self.api = api
    }

    /// The default location, falling back to the earliest created.
    var current: SavedLocation? {
        locations.first(where: \.isDefault) ?? locations.min { $0.createdAt < $1.createdAt }
    }

    /// True once a load has finished, whatever it found — `RootView` waits on this
    /// before deciding between onboarding and the app shell.
    var hasLoaded: Bool { state == .loaded }

    /// Forgets everything — sign-out.
    func reset() {
        locations = []
        state = .idle
    }

    func load() async {
        state = .loading
        do {
            locations = try await api.locations()
            state = .loaded
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Creates a location; the first one becomes the default automatically.
    @discardableResult
    func create(label: String, address: String?, latitude: Double, longitude: Double) async throws -> SavedLocation {
        let saved = try await api.createLocation(
            NewSavedLocation(
                label: label, address: address, latitude: latitude, longitude: longitude,
                isDefault: locations.isEmpty
            )
        )
        locations.append(saved)
        return saved
    }

    /// Refuses to remove the last location. Not reachable from v1's UI; here so the
    /// rule lives with the data rather than in a future screen.
    func delete(id: UUID) async throws {
        guard locations.count > 1 else { throw LocationStoreError.cannotDeleteLastLocation }
        try await api.deleteLocation(id: id)
        locations.removeAll { $0.id == id }
    }
}
