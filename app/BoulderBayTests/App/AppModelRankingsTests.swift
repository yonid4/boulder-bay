import Foundation
import Testing

@testable import BoulderBay

/// What `rankingsForSelection()` asks the backend for, and how it recovers from a stale place.
@MainActor
@Suite(.serialized)
struct AppModelRankingsTests {
    private let host = "app-model-rankings.test"

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
    /// 2026-09-13, 11:47 AM in Los Angeles.
    private static let now = Date(timeIntervalSince1970: 1_789_325_220)

    @Test func theCurrentHourLeavesAtOut() async throws {
        let (model, server) = try await makeModel(rankingsStatus: { _ in 200 })

        _ = try await model.rankingsForSelection()

        let query = try #require(server.rankingsQueries.value.last)
        #expect(query["location_id"] == model.selectedLocationID?.uuidString.lowercased())
        #expect(query["at"] == nil)
        #expect(query["limit"] == nil)
    }

    @Test func anotherHourSendsItsInstantWithAnOffset() async throws {
        let (model, server) = try await makeModel(rankingsStatus: { _ in 200 })
        model.selectedHour = Self.calendar.component(.hour, from: Self.now) + 2

        _ = try await model.rankingsForSelection(limit: 1)

        let query = try #require(server.rankingsQueries.value.last)
        let at = try #require(query["at"])
        #expect(try Date(at, strategy: .iso8601) == model.date(forHour: model.selectedHour))
        #expect(at.hasSuffix("Z"))
        #expect(query["limit"] == "1")
    }

    @Test func aDeletedPlaceFallsBackToTheDefaultAndRanksThat() async throws {
        let other = PlacesTestServer.Place(
            id: UUID(), label: "Friend", address: nil, isDefault: false, kind: "other"
        )
        let (model, server) = try await makeModel(
            extraPlaces: [other],
            rankingsStatus: { id in id == other.id.uuidString.lowercased() ? 404 : 200 }
        )
        model.selectLocation(id: other.id)
        server.places.withValue { $0.removeAll { $0.id == other.id } }

        let rankings = try await model.rankingsForSelection()

        #expect(model.selectedLocationID == RankingsFixtures.homeID)
        #expect(rankings.location.id == RankingsFixtures.homeID)
    }

    @Test func aFourOhFourWithNoNewSelectionIsReported() async throws {
        let (model, _) = try await makeModel(rankingsStatus: { _ in 404 })

        await #expect(throws: APIError.badStatus(404)) {
            _ = try await model.rankingsForSelection()
        }
    }

    @Test func otherErrorsDoNotReloadThePlaces() async throws {
        let (model, server) = try await makeModel(rankingsStatus: { _ in 500 })
        let reads = server.placeReads.value

        await #expect(throws: APIError.badStatus(500)) {
            _ = try await model.rankingsForSelection()
        }
        #expect(server.placeReads.value == reads)
    }

    // MARK: Helpers

    private func makeModel(
        extraPlaces: [PlacesTestServer.Place] = [],
        rankingsStatus: @escaping @Sendable (String?) -> Int
    ) async throws -> (AppModel, Server) {
        let server = Server(
            host: host,
            places: [
                .init(
                    id: RankingsFixtures.homeID, label: "Home", address: nil, isDefault: true,
                    kind: "home"
                )
            ] + extraPlaces,
            rankingsStatus: rankingsStatus
        )
        let now = Self.now
        let model = AppModel(
            apiClient: server.client,
            calendar: Self.calendar,
            now: { now }
        )
        await model.bootstrap()
        try #require(model.state == .loaded)
        return (model, server)
    }

    /// `PlacesTestServer`'s places API plus `/api/rankings`.
    private final class Server: Sendable {
        let client: APIClient
        let places: LockedBox<[PlacesTestServer.Place]>
        let rankingsQueries = LockedBox<[[String: String]]>([])
        let placeReads = LockedBox(0)

        init(
            host: String,
            places: [PlacesTestServer.Place],
            rankingsStatus: @escaping @Sendable (String?) -> Int
        ) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            client = APIClient(
                baseURL: URL(string: "https://\(host)")!,
                session: URLSession(configuration: configuration),
                accessToken: { "test-token" }
            )
            let box = LockedBox(places)
            self.places = box
            let queries = rankingsQueries
            let reads = placeReads
            StubURLProtocol.setHandler(forHost: host) { request in
                let url = request.url!
                let ok = { (status: Int, body: Data) in
                    (
                        HTTPURLResponse(
                            url: url, statusCode: status, httpVersion: nil, headerFields: nil
                        )!,
                        body
                    )
                }
                switch url.path {
                case "/api/me":
                    return ok(
                        200,
                        Data(#"{"data": {"id": "7878e808-a48f-4649-8a65-3feb6029a591", "display_name": "A"}}"#.utf8)
                    )
                case "/api/me/memberships":
                    return ok(200, Data(#"{"data": []}"#.utf8))
                case "/api/me/locations":
                    reads.withValue { $0 += 1 }
                    let list = box.withValue { $0.map(\.fixtureJSON).joined(separator: ", ") }
                    return ok(200, Data(#"{"data": [\#(list)]}"#.utf8))
                case "/api/rankings":
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    let query = Dictionary(
                        uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }
                    )
                    queries.withValue { $0.append(query) }
                    let status = rankingsStatus(query["location_id"])
                    return ok(
                        status,
                        status == 200 ? RankingsFixtures.body(slugs: ["mosaic"]) : Data()
                    )
                default:
                    return ok(404, Data())
                }
            }
        }
    }
}

extension LockedBox {
    fileprivate var value: Value { withValue { $0 } }
}

extension PlacesTestServer.Place {
    fileprivate var fixtureJSON: String {
        """
        {"id": "\(id.uuidString.lowercased())", "label": "\(label)", "address": null, \
        "latitude": 37.8, "longitude": -122.2, "is_default": \(isDefault), "kind": "\(kind)"}
        """
    }
}
