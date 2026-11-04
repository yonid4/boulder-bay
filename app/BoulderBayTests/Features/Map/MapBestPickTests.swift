import Foundation
import MapKit
import Testing

@testable import BoulderBay

/// The map's best-pick button: select and fly to rank 1, or say why it can't.
@MainActor
@Suite(.serialized)
struct MapBestPickTests {
    private let host = "map-best-pick.test"

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
    /// 2026-09-13, 11:47 AM in Los Angeles.
    private static let now = Date(timeIntervalSince1970: 1_789_325_220)

    @Test func selectsAndFliesToRankOne() async throws {
        let server = Server(host: host)
        let model = try await makeModel(server)

        let region = try #require(await model.findBestPick())

        #expect(model.selectedGymID == "mission")
        #expect(region.center.latitude == 37.8)
        #expect(region.center.longitude == -122.27)
        #expect(region.span.longitudeDelta == 0.12)
        #expect(model.cameraRegion?.center.latitude == 37.8)
        #expect(model.bestPickMessage == nil)
        #expect(!model.isFindingBestPick)
        #expect(server.lastQuery.withValue { $0 }["limit"] == "1")
    }

    @Test func keepsACloserZoom() async throws {
        let model = try await makeModel(Server(host: host))
        _ = model.flyTo(try #require(model.appModel.selectedLocation))
        model.cameraMoved(to: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.8, longitude: -122.2),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))

        let region = try #require(await model.findBestPick())

        #expect(region.span.longitudeDelta == 0.02)
    }

    @Test func zoomsInFromTheWholeBay() async throws {
        let model = try await makeModel(Server(host: host))
        model.cameraMoved(to: .bayArea)
        _ = model.flyTo(try #require(model.appModel.selectedLocation))
        model.cameraMoved(to: .bayArea)

        let region = try #require(await model.findBestPick())

        #expect(region.span.longitudeDelta == 0.12)
    }

    @Test func anEmptyListSaysSoAndStaysPut() async throws {
        let server = Server(host: host)
        server.slugs.withValue { $0 = [] }
        let model = try await makeModel(server)
        model.appModel.selectedHour = 23

        let region = await model.findBestPick()

        #expect(region == nil)
        #expect(model.selectedGymID == nil)
        #expect(model.bestPickMessage == "Nothing open near Home at 11 PM")

        model.dismissBestPickMessage()
        #expect(model.bestPickMessage == nil)
    }

    @Test func anEmptyListAtTheCurrentHourSaysRightNow() async throws {
        let server = Server(host: host)
        server.slugs.withValue { $0 = [] }
        let model = try await makeModel(server)

        _ = await model.findBestPick()

        #expect(model.bestPickMessage == "Nothing open near Home right now")
    }

    @Test func aFailureShowsTheMessage() async throws {
        let server = Server(host: host)
        server.status.withValue { $0 = 500 }
        let model = try await makeModel(server)

        let region = await model.findBestPick()

        #expect(region == nil)
        #expect(model.bestPickMessage == "The server returned an error (500).")
        #expect(!model.isFindingBestPick)
    }

    @Test func anAnswerForAnHourLeftBehindIsDropped() async throws {
        let server = Server(host: host)
        let model = try await makeModel(server)
        let gate = DispatchSemaphore(value: 0)
        server.gate.withValue { $0 = gate }

        let pick = Task { await model.findBestPick() }
        while server.requests.withValue({ $0 }) == 0 { await Task.yield() }
        model.appModel.selectedHour = 19
        gate.signal()
        let region = await pick.value

        #expect(region == nil)
        #expect(model.selectedGymID == nil)
        #expect(model.bestPickMessage == nil)
    }

    // MARK: Helpers

    private func makeModel(_ server: Server) async throws -> MapViewModel {
        let now = Self.now
        let appModel = AppModel(apiClient: server.client, calendar: Self.calendar, now: { now })
        await appModel.bootstrap()
        try #require(appModel.state == .loaded)
        return MapViewModel(appModel: appModel)
    }

    private final class Server: Sendable {
        let client: APIClient
        let status = LockedBox(200)
        let slugs = LockedBox(["mission", "dogpatch"])
        let gate = LockedBox<DispatchSemaphore?>(nil)
        let requests = LockedBox(0)
        let lastQuery = LockedBox<[String: String]>([:])

        init(host: String) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            client = APIClient(
                baseURL: URL(string: "https://\(host)")!,
                session: URLSession(configuration: configuration),
                accessToken: { "test-token" }
            )
            let (status, slugs, gate, requests, lastQuery) = (status, slugs, gate, requests, lastQuery)
            StubURLProtocol.setHandler(forHost: host) { request in
                let url = request.url!
                let respond = { (code: Int, body: Data) in
                    (
                        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!,
                        body
                    )
                }
                switch url.path {
                case "/api/me":
                    return respond(
                        200,
                        Data(#"{"data": {"id": "7878e808-a48f-4649-8a65-3feb6029a591", "display_name": "A"}}"#.utf8)
                    )
                case "/api/me/memberships":
                    return respond(200, Data(#"{"data": []}"#.utf8))
                case "/api/me/locations":
                    let id = RankingsFixtures.homeID.uuidString.lowercased()
                    return respond(
                        200,
                        Data(
                            """
                            {"data": [{"id": "\(id)", "label": "Home", "address": null, "latitude": 37.8,
                            "longitude": -122.2, "is_default": true, "kind": "home"}]}
                            """.utf8
                        )
                    )
                case "/api/rankings":
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    lastQuery.withValue {
                        $0 = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
                    }
                    let waiting = gate.withValue { $0 }
                    requests.withValue { $0 += 1 }
                    waiting?.wait()
                    let code = status.withValue { $0 }
                    return respond(
                        code,
                        code == 200 ? RankingsFixtures.body(slugs: slugs.withValue { $0 }) : Data()
                    )
                default:
                    return respond(404, Data())
                }
            }
        }
    }
}
