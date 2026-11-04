import Foundation
import Testing

@testable import BoulderBay

/// The places sheet's writes: each one reloads `AppModel`, and failures show in the sheet.
@MainActor
@Suite(.serialized)
struct PlacesViewModelTests {
    private let host = "places-view-model.test"

    // MARK: What each place offers

    @Test func theOnlyPlaceCannotBeDeleted() async throws {
        let (model, _, _) = try await makeModel(places: [Self.home])
        #expect(!model.canDelete)
    }

    @Test func anyPlaceCanBeDeletedWhileAnotherRemains() async throws {
        let (model, _, _) = try await makeModel(places: [Self.home, Self.friend])
        #expect(model.canDelete)
    }

    @Test func onlyAPlaceThatIsNotTheDefaultOffersMakeDefault() async throws {
        let (model, _, _) = try await makeModel(places: [Self.home, Self.friend])
        #expect(!model.canMakeDefault(model.locations[0]))
        #expect(model.canMakeDefault(model.locations[1]))
    }

    // MARK: Make default

    @Test func makeDefaultPatchesThePlaceAndReloads() async throws {
        let (model, server, appModel) = try await makeModel(places: [Self.home, Self.friend])

        await model.makeDefault(model.locations[1])

        let patch = try #require(server.requests.first { $0.method == "PATCH" })
        #expect(patch.path == "/api/me/locations/\(Self.friendID.uuidString.lowercased())")
        #expect(patch.body == ["make_default": true])
        // The server moved the default; only the reload can have told the app.
        #expect(appModel.locations.first { $0.isDefault }?.id == Self.friendID)
        #expect(model.errorMessage == nil)
        #expect(model.pendingLocationID == nil)
    }

    @Test func aConflictOnMakeDefaultShowsTheServersMessageAndDoesNotReload() async throws {
        let (model, server, appModel) = try await makeModel(places: [Self.home, Self.friend])
        let message = "Your default place changed at the same time. Try again"
        server.writeConflict.withValue { $0 = message }
        let readsBefore = server.locationReads

        await model.makeDefault(model.locations[1])

        #expect(model.errorMessage == message)
        #expect(!model.needsReload)
        #expect(server.locationReads == readsBefore)
        #expect(appModel.locations.first { $0.isDefault }?.id == Self.homeID)
    }

    // MARK: Delete

    @Test func deleteRemovesThePlaceAndReloads() async throws {
        let (model, server, appModel) = try await makeModel(places: [Self.home, Self.friend])

        await model.delete(model.locations[1])

        let delete = try #require(server.requests.first { $0.method == "DELETE" })
        #expect(delete.path == "/api/me/locations/\(Self.friendID.uuidString.lowercased())")
        #expect(appModel.locations.map(\.id) == [Self.homeID])
        #expect(model.errorMessage == nil)
    }

    @Test func deletingTheDefaultPicksUpTheOneTheServerPromoted() async throws {
        let (model, _, appModel) = try await makeModel(places: [Self.home, Self.friend])
        #expect(appModel.selectedLocationID == Self.homeID)

        await model.delete(model.locations[0])

        #expect(appModel.locations.map(\.isDefault) == [true])
        #expect(appModel.selectedLocationID == Self.friendID)
    }

    @Test func deletingTheOnlyPlaceNeverReachesTheServer() async throws {
        let (model, server, appModel) = try await makeModel(places: [Self.home])

        await model.delete(model.locations[0])

        #expect(!server.requests.contains { $0.method == "DELETE" })
        #expect(appModel.locations.map(\.id) == [Self.homeID])
    }

    @Test func aConflictOnDeleteShowsTheServersMessageAndKeepsThePlace() async throws {
        let (model, server, appModel) = try await makeModel(places: [Self.home, Self.friend])
        server.writeConflict.withValue { $0 = "You need at least one place" }
        let readsBefore = server.locationReads

        await model.delete(model.locations[1])

        #expect(model.errorMessage == "You need at least one place")
        #expect(server.locationReads == readsBefore)
        #expect(appModel.locations.count == 2)
    }

    // MARK: A failed reload

    @Test func aFailedReloadAfterAWriteShowsInTheSheetAndLeavesTheShellMounted() async throws {
        let (model, server, appModel) = try await makeModel(places: [Self.home, Self.friend])
        server.failLocationReads.withValue { $0 = true }
        let profileReadsBefore = server.profileReads

        await model.delete(model.locations[1])

        #expect(model.errorMessage == "The server returned an error (500).")
        #expect(model.needsReload)
        // `bootstrap()` would set `.loading` and unmount `AppShell`.
        #expect(appModel.state == .loaded)
        #expect(server.profileReads == profileReadsBefore)
        #expect(appModel.locations.count == 2)
    }

    @Test func retryingAFailedReloadCatchesUpAndClearsTheError() async throws {
        let (model, server, appModel) = try await makeModel(places: [Self.home, Self.friend])
        server.failLocationReads.withValue { $0 = true }
        await model.delete(model.locations[1])
        server.failLocationReads.withValue { $0 = false }

        await model.reload()

        #expect(model.errorMessage == nil)
        #expect(!model.needsReload)
        #expect(appModel.locations.map(\.id) == [Self.homeID])
    }

    @Test func retryingAFailedReloadThatFailsAgainKeepsTheError() async throws {
        let (model, server, _) = try await makeModel(places: [Self.home, Self.friend])
        server.failLocationReads.withValue { $0 = true }
        await model.delete(model.locations[1])

        await model.reload()

        #expect(model.errorMessage == "The server returned an error (500).")
        #expect(model.needsReload)
    }

    @Test func theNextActionClearsAnEarlierError() async throws {
        let (model, server, _) = try await makeModel(places: [Self.home, Self.friend])
        server.writeConflict.withValue { $0 = "Try again" }
        await model.delete(model.locations[1])
        #expect(model.errorMessage == "Try again")
        server.writeConflict.withValue { $0 = nil }

        await model.makeDefault(model.locations[1])

        #expect(model.errorMessage == nil)
    }

    // MARK: The add form

    @Test func theAddFormCreatesThePlaceAndReloads() async throws {
        let (model, server, appModel) = try await makeModel(places: [Self.home])
        let form = try await makeAddForm(model)
        form.label = "Ryan's"

        let saved = await form.save()

        #expect(saved?.label == "Ryan's")
        #expect(server.requests.contains { $0.method == "POST" })
        #expect(appModel.locations.map(\.label) == ["Home", "Ryan's"])
        #expect(form.errorMessage == nil)
    }

    @Test func aKindAlreadyTakenIsNotOfferedOnTheAddForm() async throws {
        let (model, _, _) = try await makeModel(places: [Self.home])

        let form = model.addForm(search: FakeAddressSearch())

        #expect(form.availableKinds == [.work, .other])
        #expect(form.kind == .other)
    }

    @Test func aConflictOnCreateShowsOnTheFormNotTheSheet() async throws {
        let (model, server, appModel) = try await makeModel(places: [Self.home])
        let form = try await makeAddForm(model)
        form.label = "Home again"
        server.writeConflict.withValue { $0 = "You already have a place with that label" }
        let readsBefore = server.locationReads

        let saved = await form.save()

        #expect(saved == nil)
        #expect(form.errorMessage == "You already have a place with that label")
        #expect(model.errorMessage == nil)
        #expect(server.locationReads == readsBefore)
        #expect(appModel.locations.count == 1)
    }

    /// The place exists once the POST succeeds, so the form closes rather than offering a
    /// second save that could only clash with it. The sheet below shows what went wrong.
    @Test func aFailedReloadAfterACreateClosesTheFormAndShowsInTheSheet() async throws {
        let (model, server, appModel) = try await makeModel(places: [Self.home])
        let form = try await makeAddForm(model)
        form.label = "Ryan's"
        server.failLocationReads.withValue { $0 = true }

        let saved = await form.save()

        #expect(saved?.label == "Ryan's")
        #expect(form.errorMessage == nil)
        #expect(model.errorMessage == "The server returned an error (500).")
        #expect(model.needsReload)
        #expect(appModel.state == .loaded)
    }

    // MARK: The edit form

    @Test func theEditFormUpdatesThePlaceAndReloads() async throws {
        let (model, server, appModel) = try await makeModel(places: [Self.home, Self.friend])
        let form = model.editForm(for: model.locations[1], search: FakeAddressSearch())
        form.label = "Sam's"

        let saved = await form.save()

        let patch = try #require(server.requests.first { $0.method == "PATCH" })
        #expect(patch.path == "/api/me/locations/\(Self.friendID.uuidString.lowercased())")
        #expect(patch.body == ["label": "Sam's"])
        #expect(saved?.label == "Sam's")
        #expect(appModel.locations.map(\.label) == ["Home", "Sam's"])
    }

    @Test func theEditFormKeepsThePlacesOwnKindOnOffer() async throws {
        let (model, _, _) = try await makeModel(places: [Self.home, Self.friend])

        let form = model.editForm(for: model.locations[0], search: FakeAddressSearch())

        #expect(form.availableKinds == [.home, .work, .other])
    }

    @Test func aFailedReloadAfterAnEditClosesTheFormAndShowsInTheSheet() async throws {
        let (model, server, _) = try await makeModel(places: [Self.home, Self.friend])
        let form = model.editForm(for: model.locations[1], search: FakeAddressSearch())
        form.label = "Sam's"
        server.failLocationReads.withValue { $0 = true }

        let saved = await form.save()

        #expect(saved?.label == "Sam's")
        #expect(form.errorMessage == nil)
        #expect(model.errorMessage == "The server returned an error (500).")
    }

    // MARK: Helpers

    private func makeModel(
        places: [PlacesTestServer.Place]
    ) async throws -> (PlacesViewModel, PlacesTestServer, AppModel) {
        let server = PlacesTestServer(host: host, places: places)
        let apiClient = server.makeAPIClient()
        let appModel = AppModel(apiClient: apiClient)
        await appModel.bootstrap()
        try #require(appModel.state == .loaded)
        return (PlacesViewModel(apiClient: apiClient, appModel: appModel), server, appModel)
    }

    /// An add form with an address already chosen, so it can be saved.
    private func makeAddForm(_ model: PlacesViewModel) async throws -> PlaceFormModel {
        let search = FakeAddressSearch()
        let suggestion = AddressSuggestion(title: "1 Main St", subtitle: "Oakland, CA")
        search.resolutions[suggestion] = PlaceAddress(
            address: "1 Main St, Oakland, CA", latitude: 37.8044, longitude: -122.2712
        )
        let form = model.addForm(search: search)
        await form.select(suggestion)
        try #require(form.selectedAddress != nil)
        return form
    }

    private static let homeID = UUID(uuidString: "11111111-8b7d-4e6f-9a01-2b3c4d5e6f70")!
    private static let friendID = UUID(uuidString: "22222222-8b7d-4e6f-9a01-2b3c4d5e6f70")!
    private static let home = PlacesTestServer.Place(
        id: homeID,
        label: "Home",
        address: "1 Main St, Redwood City, CA",
        isDefault: true,
        kind: "home"
    )
    private static let friend = PlacesTestServer.Place(
        id: friendID,
        label: "Ryan's",
        address: "9 Oak St, Berkeley, CA",
        isDefault: false,
        kind: "other"
    )
}
