import Foundation
import MapKit
import Observation

/// Creates the one v1 location through `LocationStore`. The form is a label plus a
/// place picked from MapKit search; saving needs both.
@MainActor
@Observable
final class LocationsViewModel {
    var label = "Home"
    private(set) var place: PlaceResult?
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    let search = PlaceSearch()
    private let locations: LocationStore
    private let rankings: RankingStore

    init(locations: LocationStore, rankings: RankingStore) {
        self.locations = locations
        self.rankings = rankings
    }

    var canSave: Bool {
        place != nil && !label.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    func pick(_ completion: MKLocalSearchCompletion) async {
        errorMessage = nil
        do {
            place = try await search.resolve(completion)
            search.query = ""
        } catch {
            errorMessage = "Couldn't look that place up. Try another result."
        }
    }

    /// Lets tests and previews skip MapKit.
    func use(place: PlaceResult) {
        self.place = place
        errorMessage = nil
    }

    func clearPlace() {
        place = nil
    }

    func save() async {
        guard let place, canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await locations.create(
                label: label.trimmingCharacters(in: .whitespaces),
                address: place.address,
                latitude: place.latitude,
                longitude: place.longitude
            )
            rankings.markStale()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
