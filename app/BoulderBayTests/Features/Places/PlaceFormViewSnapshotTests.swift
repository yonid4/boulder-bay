import SnapshotTesting
import SwiftUI
import Testing

@testable import BoulderBay

/// Reference images live in `__Snapshots__/`. To re-record after an intended visual change,
/// delete the affected PNGs and run the tests once; they fail while recording, then pass.
@MainActor
@Suite
struct PlaceFormViewSnapshotTests {
    @Test func newPlace() {
        assertForm(makeModel())
    }

    @Test func homeTakenWithSuggestions() async {
        let search = FakeAddressSearch()
        search.suggestionsByQuery["2295 Harr"] = [
            AddressSuggestion(
                title: "2295 Harrison St", subtitle: "San Francisco, CA, United States"
            ),
            AddressSuggestion(
                title: "Mission Cliffs", subtitle: "2295 Harrison St, San Francisco, CA, United States"
            ),
        ]
        let model = makeModel(existing: [Self.home], search: search)
        model.query = "2295 Harr"
        await model.searchSuggestions()

        assertForm(model)
    }

    @Test func chosenAddressWithAConflict() async {
        let search = FakeAddressSearch()
        let suggestion = AddressSuggestion(title: "1 Main St", subtitle: "Oakland, CA")
        search.resolutions[suggestion] = PlaceAddress(
            address: "1 Main St, Oakland, CA", latitude: 37.8044, longitude: -122.2712
        )
        let model = PlaceFormModel(existing: [], search: search) { _ in
            throw APIError.conflict("You already have a place with that label")
        }
        await model.select(suggestion)
        _ = await model.save()

        assertForm(model)
    }

    private func makeModel(
        existing: [SavedLocation] = [], search: FakeAddressSearch = FakeAddressSearch()
    ) -> PlaceFormModel {
        PlaceFormModel(existing: existing, search: search) { _ in Self.home }
    }

    private func assertForm(
        _ model: PlaceFormModel,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let view = PlaceFormView(model: model)
            .padding(20)
            .frame(width: 393)
            .background(Theme.background)
        assertSnapshot(
            of: view,
            // Small rendering differences between simulator OS versions shouldn't fail CI.
            as: .image(perceptualPrecision: 0.98, layout: .sizeThatFits),
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }

    private static let home = SavedLocation(
        id: UUID(),
        label: "Home",
        address: "1 Main St, Oakland, CA",
        latitude: 37.8044,
        longitude: -122.2712,
        isDefault: true,
        kind: .home
    )
}
