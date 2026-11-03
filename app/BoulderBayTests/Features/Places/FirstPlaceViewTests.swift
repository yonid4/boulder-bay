import Foundation
import Testing

@testable import BoulderBay

/// The first-place save: create the place, then refresh `AppModel` so the gate moves on.
@MainActor
@Suite(.serialized)
struct FirstPlaceViewTests {
    private let host = "first-place.test"

    @Test func savingCreatesThePlaceAndReloadsSoTheGateMovesOn() async throws {
        let created = LockedBox(false)
        stub(created: created)
        defer { StubURLProtocol.removeHandler(forHost: host) }
        let (apiClient, appModel) = await makeSignedInWithoutPlaces()
        #expect(SignedInScreen(appModel) == .firstPlace)

        let saved = try await FirstPlaceView.createFirstPlace(
            Self.body, apiClient: apiClient, appModel: appModel
        )

        #expect(saved.id == Self.placeID)
        #expect(appModel.locations.map(\.id) == [Self.placeID])
        #expect(appModel.selectedLocationID == Self.placeID)
        #expect(SignedInScreen(appModel) == .shell)
    }

    @Test func aConflictIsRethrownForTheFormAndNothingReloads() async {
        let locationReads = LockedBox(0)
        StubURLProtocol.setHandler(forHost: host) { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/me/locations"):
                return (
                    Self.response(for: request, status: 409),
                    Data(#"{"detail": "You already have a place with that label"}"#.utf8)
                )
            case ("GET", "/api/me/locations"):
                locationReads.withValue { $0 += 1 }
                return (Self.response(for: request, status: 200), Self.emptyList)
            default:
                return Self.bootstrapResponse(for: request)
            }
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }
        let (apiClient, appModel) = await makeSignedInWithoutPlaces()
        let readsAfterBootstrap = locationReads.withValue { $0 }

        await #expect(throws: APIError.conflict("You already have a place with that label")) {
            try await FirstPlaceView.createFirstPlace(
                Self.body, apiClient: apiClient, appModel: appModel
            )
        }

        #expect(locationReads.withValue { $0 } == readsAfterBootstrap)
        #expect(SignedInScreen(appModel) == .firstPlace)
    }

    /// The place exists once the POST succeeds, so a failed refresh mustn't leave the user on
    /// a form whose next save would only clash with it. A full reload finds it instead.
    @Test func aFailedReloadAfterTheSaveFallsBackToAFullReload() async throws {
        let created = LockedBox(false)
        let failNextRead = LockedBox(false)
        StubURLProtocol.setHandler(forHost: host) { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/me/locations"):
                created.withValue { $0 = true }
                failNextRead.withValue { $0 = true }
                return (Self.response(for: request, status: 201), Self.placeEnvelope)
            case ("GET", "/api/me/locations"):
                let shouldFail = failNextRead.withValue { value -> Bool in
                    defer { value = false }
                    return value
                }
                if shouldFail { return (Self.response(for: request, status: 500), Data()) }
                return (
                    Self.response(for: request, status: 200),
                    created.withValue { $0 } ? Self.placeList : Self.emptyList
                )
            default:
                return Self.bootstrapResponse(for: request)
            }
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }
        let (apiClient, appModel) = await makeSignedInWithoutPlaces()

        let saved = try await FirstPlaceView.createFirstPlace(
            Self.body, apiClient: apiClient, appModel: appModel
        )

        #expect(saved.id == Self.placeID)
        #expect(appModel.state == .loaded)
        #expect(appModel.locations.map(\.id) == [Self.placeID])
        #expect(SignedInScreen(appModel) == .shell)
    }

    // MARK: Helpers

    private func makeSignedInWithoutPlaces() async -> (APIClient, AppModel) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let apiClient = APIClient(
            baseURL: URL(string: "https://\(host)")!,
            session: URLSession(configuration: configuration),
            accessToken: { "test-token" }
        )
        let appModel = AppModel(apiClient: apiClient)
        await appModel.bootstrap()
        return (apiClient, appModel)
    }

    /// No places until the POST lands, then the one it created.
    private func stub(created: LockedBox<Bool>) {
        StubURLProtocol.setHandler(forHost: host) { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/me/locations"):
                created.withValue { $0 = true }
                return (Self.response(for: request, status: 201), Self.placeEnvelope)
            case ("GET", "/api/me/locations"):
                return (
                    Self.response(for: request, status: 200),
                    created.withValue { $0 } ? Self.placeList : Self.emptyList
                )
            default:
                return Self.bootstrapResponse(for: request)
            }
        }
    }

    /// The profile and memberships `bootstrap()` loads alongside the places.
    nonisolated private static func bootstrapResponse(
        for request: URLRequest
    ) -> (HTTPURLResponse, Data) {
        switch request.url?.path {
        case "/api/me":
            (
                response(for: request, status: 200),
                Data(
                    #"{"data": {"id": "7878e808-a48f-4649-8a65-3feb6029a591", "display_name": "Alex Rivera"}}"#
                        .utf8
                )
            )
        case "/api/me/memberships":
            (response(for: request, status: 200), Data(#"{"data": []}"#.utf8))
        default:
            (response(for: request, status: 404), Data())
        }
    }

    nonisolated private static func response(
        for request: URLRequest, status: Int
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private static let body = CreateSavedLocation(
        label: "Home",
        kind: .home,
        address: "1 Main St, Oakland, CA",
        latitude: 37.8044,
        longitude: -122.2712
    )

    nonisolated private static let placeID = UUID(
        uuidString: "3f2a9c1e-8b7d-4e6f-9a01-2b3c4d5e6f70"
    )!

    nonisolated private static let place = """
        {
            "id": "\(placeID.uuidString.lowercased())",
            "label": "Home",
            "address": "1 Main St, Oakland, CA",
            "latitude": 37.8044,
            "longitude": -122.2712,
            "is_default": true,
            "kind": "home"
        }
        """
    nonisolated private static let placeEnvelope = Data(#"{"data": \#(place)}"#.utf8)
    nonisolated private static let placeList = Data(#"{"data": [\#(place)]}"#.utf8)
    nonisolated private static let emptyList = Data(#"{"data": []}"#.utf8)
}

private extension SignedInScreen {
    @MainActor
    init(_ appModel: AppModel) {
        self.init(state: appModel.state, hasLocations: !appModel.locations.isEmpty)
    }
}
