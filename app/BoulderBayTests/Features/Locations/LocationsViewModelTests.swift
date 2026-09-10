import Foundation
import Testing

@testable import BoulderBay

@MainActor
struct LocationsViewModelTests {
    private func makeModel() async -> (SpyAPIClient, LocationStore, LocationsViewModel) {
        let profile = UserProfile(id: UUID(), email: "new@example.com", displayName: nil)
        let api = SpyAPIClient(inner: MockAPIClient(account: .fresh(profile: profile)))
        let locations = LocationStore(api: api)
        await locations.load()
        let rankings = RankingStore(api: api, locations: locations)
        return (api, locations, LocationsViewModel(locations: locations, rankings: rankings))
    }

    @Test func needsAPlaceAndALabel() async {
        let (_, _, model) = await makeModel()
        #expect(!model.canSave)

        model.use(place: PlaceResult(title: "Redwood City", address: "Redwood City, CA", latitude: 37.48, longitude: -122.23))
        #expect(model.canSave)

        model.label = "   "
        #expect(!model.canSave)
    }

    @Test func saveCreatesTheDefaultLocation() async {
        let (api, locations, model) = await makeModel()
        model.use(place: PlaceResult(title: "Redwood City", address: "Redwood City, CA", latitude: 37.48, longitude: -122.23))
        model.label = " Home "

        await model.save()

        #expect(model.errorMessage == nil)
        #expect(locations.current?.label == "Home")
        #expect(locations.current?.address == "Redwood City, CA")
        #expect(locations.current?.isDefault == true)
        #expect(api.calls.contains(.createLocation("Home")))
    }

    @Test func saveFailureIsShown() async {
        let (api, locations, model) = await makeModel()
        model.use(place: PlaceResult(title: "X", address: "X", latitude: 1, longitude: 1))
        api.failNext(with: .badStatus(500))

        await model.save()

        #expect(model.errorMessage != nil)
        #expect(locations.current == nil)
    }
}
