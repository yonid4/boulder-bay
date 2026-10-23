import Foundation
import Testing

@testable import BoulderBay

@MainActor
@Suite
struct PlaceFormModelTests {
    // MARK: Kind availability

    @Test func everyKindIsAvailableWithoutPlaces() {
        #expect(PlaceFormModel.availableKinds(existing: [], editing: nil) == [.home, .work, .other])
    }

    @Test func aTakenHomeOrWorkIsHidden() {
        let home = Self.place(label: "Home", kind: .home)
        let work = Self.place(label: "Work", kind: .work)
        let gym = Self.place(label: "Gym", kind: .other)

        #expect(PlaceFormModel.availableKinds(existing: [home], editing: nil) == [.work, .other])
        #expect(PlaceFormModel.availableKinds(existing: [work], editing: nil) == [.home, .other])
        #expect(PlaceFormModel.availableKinds(existing: [home, work, gym], editing: nil) == [.other])
    }

    @Test func editingAPlaceKeepsItsOwnKindAvailable() {
        let home = Self.place(label: "Home", kind: .home)
        let work = Self.place(label: "Work", kind: .work)

        #expect(
            PlaceFormModel.availableKinds(existing: [home, work], editing: home.id) == [.home, .other]
        )
    }

    @Test func formOffersOnlyTheAvailableKinds() {
        let model = makeCreateModel(existing: [Self.place(label: "Home", kind: .home)])
        #expect(model.availableKinds == [.work, .other])
    }

    // MARK: Kind and label

    @Test func newPlaceStartsAsHomeWithItsLabel() {
        let model = makeCreateModel()
        #expect(model.kind == .home)
        #expect(model.label == "Home")
    }

    @Test func aTakenPreferredKindFallsBackToOther() {
        let model = makeCreateModel(existing: [Self.place(label: "Home", kind: .home)])
        #expect(model.kind == .other)
        #expect(model.label.isEmpty)
    }

    @Test func anAvailablePreferredKindIsUsed() {
        let model = makeCreateModel(preferredKind: .work)
        #expect(model.kind == .work)
        #expect(model.label == "Work")
    }

    @Test func switchingKindReplacesAPrefilledLabel() {
        let model = makeCreateModel()

        model.kind = .work
        #expect(model.label == "Work")

        model.kind = .other
        #expect(model.label.isEmpty)

        model.kind = .home
        #expect(model.label == "Home")
    }

    @Test func switchingKindKeepsATypedLabel() {
        let model = makeCreateModel()
        model.label = "Mom's place"

        model.kind = .work

        #expect(model.label == "Mom's place")
    }

    // MARK: Address search

    @Test func typingLoadsSuggestions() async {
        let search = FakeAddressSearch()
        search.suggestionsByQuery["2295 Harr"] = [Self.missionCliffs]
        let model = makeCreateModel(search: search)

        model.query = "2295 Harr"
        await model.searchSuggestions()

        #expect(model.suggestions == [Self.missionCliffs])
    }

    @Test func aBlankQueryClearsSuggestionsWithoutSearching() async {
        let search = FakeAddressSearch()
        search.suggestionsByQuery["2295"] = [Self.missionCliffs]
        let model = makeCreateModel(search: search)
        model.query = "2295"
        await model.searchSuggestions()

        model.query = "   "
        await model.searchSuggestions()

        #expect(model.suggestions.isEmpty)
        #expect(search.queries == ["2295"])
    }

    @Test func aFailedSearchShowsNoSuggestions() async {
        let search = FakeAddressSearch()
        search.suggestionsError = URLError(.notConnectedToInternet)
        let model = makeCreateModel(search: search)

        model.query = "2295"
        await model.searchSuggestions()

        #expect(model.suggestions.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func choosingASuggestionResolvesItsAddressAndCoordinates() async {
        let search = Self.searchWithMissionCliffs()
        let model = makeCreateModel(search: search)
        model.query = "2295 Harr"
        await model.searchSuggestions()

        await model.select(Self.missionCliffs)

        #expect(model.selectedAddress == Self.missionCliffsAddress)
        #expect(model.query == "2295 Harrison St, San Francisco, CA")
        #expect(model.suggestions.isEmpty)
        #expect(!model.isResolving)
    }

    @Test func aChosenAddressNeedsNoMoreSuggestions() async {
        let search = Self.searchWithMissionCliffs()
        let model = makeCreateModel(search: search)
        await model.select(Self.missionCliffs)

        await model.searchSuggestions()

        #expect(model.suggestions.isEmpty)
        #expect(search.queries.isEmpty)
    }

    @Test func editingTheQueryDropsTheChosenAddress() async {
        let model = makeCreateModel(search: Self.searchWithMissionCliffs())
        await model.select(Self.missionCliffs)

        model.query = "2295 Harrison"

        #expect(model.selectedAddress == nil)
    }

    @Test func anUnresolvableSuggestionShowsAMessage() async {
        let model = makeCreateModel(search: FakeAddressSearch())

        await model.select(Self.missionCliffs)

        #expect(model.selectedAddress == nil)
        #expect(model.errorMessage == "Couldn't find that address. Try another one.")
        #expect(!model.isResolving)
    }

    // MARK: Creating

    @Test func savingNeedsALabelAndAChosenAddress() async {
        let model = makeCreateModel(search: Self.searchWithMissionCliffs())
        #expect(!model.canSave)

        await model.select(Self.missionCliffs)
        #expect(model.canSave)

        model.label = "   "
        #expect(!model.canSave)
    }

    @Test func savingCreatesThePlaceFromTheForm() async throws {
        let sent = LockedBox<[CreateSavedLocation]>([])
        let model = makeCreateModel(search: Self.searchWithMissionCliffs()) { body in
            sent.withValue { $0.append(body) }
            return Self.place(label: body.label, kind: body.kind)
        }
        model.kind = .other
        model.label = "  Climbing gym  "
        await model.select(Self.missionCliffs)

        let saved = try #require(await model.save())

        #expect(
            sent.withValue { $0 } == [
                CreateSavedLocation(
                    label: "Climbing gym",
                    kind: .other,
                    address: "2295 Harrison St, San Francisco, CA",
                    latitude: 37.7609,
                    longitude: -122.4126
                )
            ]
        )
        #expect(saved.label == "Climbing gym")
        #expect(model.errorMessage == nil)
        #expect(!model.isSaving)
    }

    @Test func aConflictIsShownAsTheServerWordsIt() async {
        let model = makeCreateModel(search: Self.searchWithMissionCliffs()) { _ in
            throw APIError.conflict("You already have a home")
        }
        await model.select(Self.missionCliffs)

        let saved = await model.save()

        #expect(saved == nil)
        #expect(model.errorMessage == "You already have a home")
        #expect(!model.isSaving)
    }

    @Test func otherSaveFailuresGetTheirOwnMessages() async {
        let cases: [(any Error, String)] = [
            (APIError.badStatus(401), "Your session has expired. Sign in again."),
            (APIError.badStatus(500), "The server returned an error (500)."),
            (APIError.decoding("bad"), "The server sent something unexpected."),
            (URLError(.notConnectedToInternet), "Couldn't reach the server. Check your connection."),
        ]
        for (error, message) in cases {
            let model = makeCreateModel(search: Self.searchWithMissionCliffs()) { _ in throw error }
            await model.select(Self.missionCliffs)

            _ = await model.save()

            #expect(model.errorMessage == message)
        }
    }

    @Test func aRetryClearsTheLastError() async {
        let failFirst = LockedBox(true)
        let model = makeCreateModel(search: Self.searchWithMissionCliffs()) { body in
            if failFirst.withValue({ value in defer { value = false }; return value }) {
                throw APIError.conflict("You already have a place with that label")
            }
            return Self.place(label: body.label, kind: body.kind)
        }
        await model.select(Self.missionCliffs)
        _ = await model.save()

        let saved = await model.save()

        #expect(saved != nil)
        #expect(model.errorMessage == nil)
    }

    // MARK: Editing

    @Test func editingStartsFromThePlace() {
        let home = Self.place(label: "Home", kind: .home, address: "1 Main St, Oakland, CA")
        let model = makeEditModel(home, existing: [home])

        #expect(model.kind == .home)
        #expect(model.label == "Home")
        #expect(model.query == "1 Main St, Oakland, CA")
        #expect(model.selectedAddress?.latitude == home.latitude)
        #expect(model.isEditing)
    }

    @Test func anUnchangedPlaceCannotBeSaved() {
        let home = Self.place(label: "Home", kind: .home, address: "1 Main St, Oakland, CA")
        let model = makeEditModel(home, existing: [home])

        #expect(!model.canSave)

        model.label = "Casa"
        #expect(model.canSave)
    }

    @Test func savingAnEditSendsOnlyWhatChanged() async throws {
        let home = Self.place(label: "Home", kind: .home, address: "1 Main St, Oakland, CA")
        let sent = LockedBox<[UpdateSavedLocation]>([])
        let model = makeEditModel(home, existing: [home]) { id, changes in
            #expect(id == home.id)
            sent.withValue { $0.append(changes) }
            return home
        }

        model.label = "Casa"
        _ = try #require(await model.save())

        #expect(sent.withValue { $0 } == [UpdateSavedLocation(label: "Casa")])
    }

    @Test func aNewAddressSendsItsCoordinatesToo() async throws {
        let home = Self.place(label: "Home", kind: .home, address: "1 Main St, Oakland, CA")
        let sent = LockedBox<[UpdateSavedLocation]>([])
        let model = makeEditModel(home, existing: [home], search: Self.searchWithMissionCliffs()) {
            _, changes in
            sent.withValue { $0.append(changes) }
            return home
        }

        model.kind = .other
        model.label = "Old place"
        await model.select(Self.missionCliffs)
        _ = try #require(await model.save())

        #expect(
            sent.withValue { $0 } == [
                UpdateSavedLocation(
                    label: "Old place",
                    kind: .other,
                    address: "2295 Harrison St, San Francisco, CA",
                    latitude: 37.7609,
                    longitude: -122.4126
                )
            ]
        )
    }

    @Test func aPlaceWithoutAnAddressCanStillBeRenamed() {
        let gym = Self.place(label: "Gym", kind: .other, address: nil)
        let model = makeEditModel(gym, existing: [gym])

        #expect(model.query.isEmpty)
        #expect(model.selectedAddress != nil)

        model.label = "Climbing gym"
        #expect(model.canSave)
    }

    // MARK: Helpers

    private func makeCreateModel(
        existing: [SavedLocation] = [],
        preferredKind: LocationKind = .home,
        search: FakeAddressSearch = FakeAddressSearch(),
        create: @escaping @MainActor (CreateSavedLocation) async throws -> SavedLocation = {
            Self.place(label: $0.label, kind: $0.kind)
        }
    ) -> PlaceFormModel {
        PlaceFormModel(
            existing: existing,
            preferredKind: preferredKind,
            search: search,
            create: create
        )
    }

    private func makeEditModel(
        _ location: SavedLocation,
        existing: [SavedLocation],
        search: FakeAddressSearch = FakeAddressSearch(),
        update: @escaping @MainActor (UUID, UpdateSavedLocation) async throws -> SavedLocation = {
            _, _ in Self.place(label: "Unused", kind: .other)
        }
    ) -> PlaceFormModel {
        PlaceFormModel(editing: location, existing: existing, search: search, update: update)
    }

    private static let missionCliffs = AddressSuggestion(
        title: "Mission Cliffs", subtitle: "2295 Harrison St, San Francisco, CA, United States"
    )

    private static let missionCliffsAddress = PlaceAddress(
        address: "2295 Harrison St, San Francisco, CA", latitude: 37.7609, longitude: -122.4126
    )

    private static func searchWithMissionCliffs() -> FakeAddressSearch {
        let search = FakeAddressSearch()
        search.resolutions[missionCliffs] = missionCliffsAddress
        return search
    }

    private static func place(
        label: String, kind: LocationKind, address: String? = "1 Main St, Oakland, CA"
    ) -> SavedLocation {
        SavedLocation(
            id: UUID(),
            label: label,
            address: address,
            latitude: 37.8044,
            longitude: -122.2712,
            isDefault: false,
            kind: kind
        )
    }
}
