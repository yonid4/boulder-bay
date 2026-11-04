import SnapshotTesting
import SwiftUI
import Testing

@testable import BoulderBay

/// Reference images live in `__Snapshots__/`. To re-record after an intended visual change,
/// delete the affected PNGs and run the tests once; they fail while recording, then pass.
@MainActor
@Suite(.serialized)
struct PlacesViewSnapshotTests {
    private let host = "places-snapshot.test"

    @Test func severalPlacesWithTheDefaultTagged() async throws {
        let (model, _) = try await makeModel(places: Self.threePlaces)
        assertScreen(PlacesView(viewModel: model))
    }

    @Test func noAddressAndALongOne() async throws {
        let (model, _) = try await makeModel(places: [
            Self.threePlaces[0],
            .init(id: UUID(), label: "Trailhead", address: nil, isDefault: false, kind: "other"),
            .init(
                id: UUID(),
                label: "A place with a rather long label for one row",
                address: "1234 Extraordinarily Long Boulevard Name, South San Francisco, CA",
                isDefault: false,
                kind: "work"
            ),
        ])
        assertScreen(PlacesView(viewModel: model))
    }

    @Test func aConflictShowsAboveTheList() async throws {
        let (model, server) = try await makeModel(places: Self.threePlaces)
        server.writeConflict.withValue {
            $0 = "Your default place changed at the same time. Try again"
        }
        await model.makeDefault(model.locations[1])
        assertScreen(PlacesView(viewModel: model))
    }

    @Test func aFailedReloadOffersARetry() async throws {
        let (model, server) = try await makeModel(places: Self.threePlaces)
        server.failLocationReads.withValue { $0 = true }
        await model.delete(model.locations[2])
        assertScreen(PlacesView(viewModel: model))
    }

    @Test func theAddForm() async throws {
        let (model, _) = try await makeModel(places: [Self.threePlaces[0]])
        assertScreen(PlaceEditorView(model: model.addForm(search: FakeAddressSearch())))
    }

    @Test func theEditForm() async throws {
        let (model, _) = try await makeModel(places: Self.threePlaces)
        assertScreen(
            PlaceEditorView(
                model: model.editForm(for: model.locations[1], search: FakeAddressSearch())
            )
        )
    }

    // MARK: Helpers

    private func makeModel(
        places: [PlacesTestServer.Place]
    ) async throws -> (PlacesViewModel, PlacesTestServer) {
        let server = PlacesTestServer(host: host, places: places)
        let apiClient = server.makeAPIClient()
        let appModel = AppModel(apiClient: apiClient)
        await appModel.bootstrap()
        try #require(appModel.state == .loaded)
        return (PlacesViewModel(apiClient: apiClient, appModel: appModel), server)
    }

    private static let threePlaces: [PlacesTestServer.Place] = [
        .init(
            id: UUID(uuidString: "11111111-8b7d-4e6f-9a01-2b3c4d5e6f70")!,
            label: "Home",
            address: "1 Main St, Redwood City, CA",
            isDefault: true,
            kind: "home"
        ),
        .init(
            id: UUID(uuidString: "22222222-8b7d-4e6f-9a01-2b3c4d5e6f70")!,
            label: "Office",
            address: "500 Howard St, San Francisco, CA",
            isDefault: false,
            kind: "work"
        ),
        .init(
            id: UUID(uuidString: "33333333-8b7d-4e6f-9a01-2b3c4d5e6f70")!,
            label: "Ryan's",
            address: "9 Oak St, Berkeley, CA",
            isDefault: false,
            kind: "other"
        ),
    ]

    private func assertScreen(
        _ screen: some View,
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
