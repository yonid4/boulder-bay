import Foundation

/// Drives the add / edit place form: the kind picker, the label, and the address search.
///
/// It doesn't own the places list. The host passes the places that exist (for the one-home,
/// one-work rule) and the call that saves, so the onboarding gate and the places sheet can
/// each route the save through whatever keeps their list current.
@MainActor
@Observable
final class PlaceFormModel {
    /// A save the host performs, e.g. `apiClient.createLocation` or a shared-state wrapper.
    typealias Create = @MainActor (CreateSavedLocation) async throws -> SavedLocation
    typealias Update = @MainActor (UUID, UpdateSavedLocation) async throws -> SavedLocation

    private enum Action {
        case create(Create)
        case update(SavedLocation, Update)
    }

    /// Switching kind swaps a prefilled "Home" / "Work" label, but never one the user typed.
    var kind: LocationKind {
        didSet {
            guard kind != oldValue, label == oldValue.defaultLabel else { return }
            label = kind.defaultLabel
        }
    }

    var label: String

    /// The address search text. Typing over a chosen address drops it until another is chosen.
    var query: String {
        didSet {
            guard query != oldValue, query != (selectedAddress?.address ?? "") else { return }
            selectedAddress = nil
        }
    }

    private(set) var suggestions: [AddressSuggestion] = []
    /// The address and coordinates that will be saved; an edited place starts with its own.
    private(set) var selectedAddress: PlaceAddress?
    private(set) var isResolving = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    /// The kinds the picker offers: home and work only while the user has none of them.
    let availableKinds: [LocationKind]

    private let action: Action
    private let search: any AddressSearching

    /// A form for a new place. It starts on `preferredKind` when that kind is free, else `other`.
    init(
        existing: [SavedLocation],
        preferredKind: LocationKind = .home,
        search: any AddressSearching,
        create: @escaping Create
    ) {
        let available = Self.availableKinds(existing: existing, editing: nil)
        let kind = available.contains(preferredKind) ? preferredKind : .other
        self.availableKinds = available
        self.kind = kind
        self.label = kind.defaultLabel
        self.query = ""
        self.search = search
        self.action = .create(create)
    }

    /// A form for changing `location`. Only the fields the user changes are sent.
    init(
        editing location: SavedLocation,
        existing: [SavedLocation],
        search: any AddressSearching,
        update: @escaping Update
    ) {
        self.availableKinds = Self.availableKinds(existing: existing, editing: location.id)
        self.kind = location.kind
        self.label = location.label
        self.query = location.address ?? ""
        self.selectedAddress = PlaceAddress(
            address: location.address, latitude: location.latitude, longitude: location.longitude
        )
        self.search = search
        self.action = .update(location, update)
    }

    var isEditing: Bool {
        if case .update = action { return true }
        return false
    }

    var canSave: Bool {
        guard !isSaving, !isResolving, !trimmedLabel.isEmpty, selectedAddress != nil else {
            return false
        }
        guard availableKinds.contains(kind) else { return false }
        if case .update(let location, _) = action {
            return changes(to: location) != UpdateSavedLocation()
        }
        return true
    }

    /// At most one home and one work: a taken kind is hidden, unless it's the place being edited.
    static func availableKinds(existing: [SavedLocation], editing id: UUID?) -> [LocationKind] {
        let taken = Set(existing.filter { $0.id != id }.map(\.kind))
        return LocationKind.allCases.filter { $0 == .other || !taken.contains($0) }
    }

    /// Loads suggestions for the current query. The view runs this from `.task(id: query)`,
    /// so a newer keystroke cancels an older search.
    func searchSuggestions() async {
        let query = query
        guard selectedAddress == nil,
            !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            suggestions = []
            return
        }

        // A failed search just shows nothing; the user can keep typing.
        let found = (try? await search.suggestions(for: query)) ?? []
        guard !Task.isCancelled, query == self.query else { return }
        suggestions = found
    }

    /// Resolves the chosen suggestion to the address and coordinates that will be saved.
    func select(_ suggestion: AddressSuggestion) async {
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }

        do {
            let address = try await search.resolve(suggestion)
            // Query first: setting it drops the old selection, then the new one replaces it.
            query = address.address ?? suggestion.text
            selectedAddress = address
            suggestions = []
        } catch {
            errorMessage = "Couldn't find that address. Try another one."
        }
    }

    /// Saves the place and returns it, or returns `nil` and sets `errorMessage`.
    func save() async -> SavedLocation? {
        guard canSave, let address = selectedAddress else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            switch action {
            case .create(let create):
                return try await create(
                    CreateSavedLocation(
                        label: trimmedLabel,
                        kind: kind,
                        address: address.address,
                        latitude: address.latitude,
                        longitude: address.longitude
                    )
                )
            case .update(let location, let update):
                return try await update(location.id, changes(to: location))
            }
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func changes(to location: SavedLocation) -> UpdateSavedLocation {
        var changes = UpdateSavedLocation()
        if trimmedLabel != location.label { changes.label = trimmedLabel }
        if kind != location.kind { changes.kind = kind }
        if let address = selectedAddress,
            address.latitude != location.latitude || address.longitude != location.longitude
                || address.address != location.address
        {
            changes.address = .some(address.address)
            changes.latitude = address.latitude
            changes.longitude = address.longitude
        }
        return changes
    }

    private static func message(for error: any Error) -> String {
        switch error {
        // The backend words label, home and work clashes for the user already.
        case APIError.conflict(let message):
            message
        case APIError.badStatus(401):
            "Your session has expired. Sign in again."
        case APIError.badStatus(let code):
            "The server returned an error (\(code))."
        case APIError.decoding:
            "The server sent something unexpected."
        default:
            "Couldn't reach the server. Check your connection."
        }
    }
}
