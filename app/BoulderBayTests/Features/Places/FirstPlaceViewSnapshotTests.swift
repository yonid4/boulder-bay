import SnapshotTesting
import SwiftUI
import Testing

@testable import BoulderBay

/// Reference images live in `__Snapshots__/`. To re-record after an intended visual change,
/// delete the affected PNGs and run the tests once; they fail while recording, then pass.
@MainActor
@Suite
struct FirstPlaceViewSnapshotTests {
    @Test func emptyForm() {
        assertScreen(FirstPlaceView(model: makeModel(), onSignOut: {}))
    }

    @Test func aConflictShowsTheServersMessage() async {
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

        assertScreen(FirstPlaceView(model: model, onSignOut: {}))
    }

    private func makeModel() -> PlaceFormModel {
        PlaceFormModel(existing: [], search: FakeAddressSearch()) { _ in
            throw CancellationError()
        }
    }

    private func assertScreen(
        _ screen: FirstPlaceView,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        assertSnapshot(
            of: screen,
            // A 393 × 852 pt phone. Small rendering differences between simulator OS
            // versions shouldn't fail CI.
            as: .image(perceptualPrecision: 0.98, layout: .fixed(width: 393, height: 852)),
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}
