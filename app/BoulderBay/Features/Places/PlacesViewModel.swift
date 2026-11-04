import Foundation

/// Drives the places sheet: the writes it makes itself and the saves its add / edit form
/// makes. Every successful write refetches the places, since the server may have moved the
/// default.
///
/// A failed refetch stays in the sheet. `AppModel.bootstrap()` isn't a fallback here: it sets
/// `.loading`, which unmounts `AppShell` and loses its route and drawer.
@MainActor
@Observable
final class PlacesViewModel {
    /// What went wrong with the last action, for the sheet to show.
    private(set) var errorMessage: String?
    /// A write succeeded but the refetch after it failed, so the list may be out of date.
    private(set) var needsReload = false
    /// The place with a make-default or delete in flight. Only one runs at a time.
    private(set) var pendingLocationID: UUID?

    private let apiClient: APIClient
    private let appModel: AppModel

    init(apiClient: APIClient, appModel: AppModel) {
        self.apiClient = apiClient
        self.appModel = appModel
    }

    var locations: [SavedLocation] {
        appModel.locationsInDisplayOrder
    }

    /// The last remaining place can't go, a UI mirror of the API's 409.
    var canDelete: Bool {
        locations.count > 1
    }

    /// A place stops being the default only when another takes over, so the default itself
    /// has nothing to offer.
    func canMakeDefault(_ location: SavedLocation) -> Bool {
        !location.isDefault
    }

    func makeDefault(_ location: SavedLocation) async {
        guard canMakeDefault(location) else { return }
        await write(to: location) { apiClient in
            _ = try await apiClient.updateLocation(
                id: location.id, UpdateSavedLocation(makeDefault: true)
            )
        }
    }

    func delete(_ location: SavedLocation) async {
        guard canDelete else { return }
        await write(to: location) { apiClient in
            try await apiClient.deleteLocation(id: location.id)
        }
    }

    /// Refetches the places. A failure sets `errorMessage` and `needsReload`. A reload that a
    /// newer one replaced changes nothing, so it can't clear that one's error.
    func reload() async {
        do {
            guard try await appModel.reloadLocations() else { return }
            errorMessage = nil
            needsReload = false
        } catch {
            errorMessage = APIError.message(for: error)
            needsReload = true
        }
    }

    // MARK: Forms

    // Once a form's save has succeeded the place exists, so a failed refetch isn't thrown back
    // at the form, where a second save could only clash with the first. `reload()` keeps the
    // error for the sheet underneath.

    /// A form for a new place. Saving creates it and refreshes the list.
    func addForm(search: any AddressSearching) -> PlaceFormModel {
        PlaceFormModel(existing: locations, search: search) { [self] body in
            let saved = try await apiClient.createLocation(body)
            await reload()
            return saved
        }
    }

    /// A form for changing `location`. Saving updates it and refreshes the list.
    func editForm(for location: SavedLocation, search: any AddressSearching) -> PlaceFormModel {
        PlaceFormModel(editing: location, existing: locations, search: search) { [self] id, changes in
            let saved = try await apiClient.updateLocation(id: id, changes)
            await reload()
            return saved
        }
    }

    // MARK: Private

    private func write(
        to location: SavedLocation, _ request: (APIClient) async throws -> Void
    ) async {
        guard pendingLocationID == nil else { return }
        pendingLocationID = location.id
        defer { pendingLocationID = nil }
        errorMessage = nil

        do {
            try await request(apiClient)
        } catch {
            errorMessage = APIError.message(for: error)
            return
        }
        await reload()
    }
}
