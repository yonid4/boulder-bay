import Foundation
import Testing

@testable import BoulderBay

@MainActor
@Suite(.serialized)
struct RankingsViewModelTests {
    private let host = "rankings-view-model.test"

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
    /// 2026-09-13, 11:47 AM in Los Angeles.
    private static let now = Date(timeIntervalSince1970: 1_789_325_220)

    @Test func startsLoadingThenShowsTheRankings() async throws {
        let server = Server(host: host)
        let model = try await makeModel(server)
        #expect(model.phase == .loading)

        await model.loadIfNeeded()

        let rankings = try #require(loadedRankings(model))
        #expect(rankings.rankedGyms.map(\.gym.slug) == ["mosaic", "dogpatch"])
    }

    @Test func aRepeatedAppearanceDoesNotRefetch() async throws {
        let server = Server(host: host)
        let model = try await makeModel(server)

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(server.rankingsRequests == 1)
    }

    @Test func aLoadRefetchesEvenWithAListLoaded() async throws {
        let server = Server(host: host)
        let model = try await makeModel(server)
        await model.loadIfNeeded()

        await model.load()

        #expect(server.rankingsRequests == 2)
    }

    @Test func anotherHourHidesTheOldListUntilItsOwnArrives() async throws {
        let server = Server(host: host)
        let model = try await makeModel(server)
        await model.loadIfNeeded()

        model.appModel.selectedHour = 19

        #expect(model.phase == .loading)
        await model.loadIfNeeded()
        #expect(loadedRankings(model) != nil)
        #expect(server.rankingsRequests == 2)
    }

    @Test func aFailedFirstLoadShowsTheFailureAndRetryRecovers() async throws {
        let server = Server(host: host)
        server.rankingsStatus.withValue { $0 = 500 }
        let model = try await makeModel(server)

        await model.loadIfNeeded()
        #expect(model.phase == .failed("The server returned an error (500)."))

        server.rankingsStatus.withValue { $0 = 200 }
        await model.load()
        #expect(loadedRankings(model) != nil)
    }

    @Test func aFailedRefreshKeepsTheListWithABanner() async throws {
        let server = Server(host: host)
        let model = try await makeModel(server)
        await model.loadIfNeeded()

        server.rankingsStatus.withValue { $0 = 500 }
        await model.load()

        guard case .loaded(let rankings, let refreshError) = model.phase else {
            Issue.record("expected the old list to stay")
            return
        }
        #expect(rankings.rankedGyms.count == 2)
        #expect(refreshError == "The server returned an error (500).")
    }

    @Test func aSlowAnswerForAnOldHourIsDropped() async throws {
        let server = Server(host: host)
        let model = try await makeModel(server)
        // The first request (the old hour) answers only after the second has finished.
        server.gate.withValue { $0 = DispatchSemaphore(value: 0) }
        let first = Task { await model.load() }
        while server.rankingsRequests == 0 { await Task.yield() }

        server.slugs.withValue { $0 = ["newer"] }
        model.appModel.selectedHour = 19
        server.gate.withValue { $0?.signal(); $0 = nil }
        await model.load()
        await first.value

        let rankings = try #require(loadedRankings(model))
        #expect(rankings.rankedGyms.map(\.gym.slug) == ["newer"])
    }

    // MARK: Helpers

    private func loadedRankings(_ model: RankingsViewModel) -> Rankings? {
        if case .loaded(let rankings, _) = model.phase { return rankings }
        return nil
    }

    private func makeModel(_ server: Server) async throws -> RankingsViewModel {
        let now = Self.now
        let appModel = AppModel(apiClient: server.client, calendar: Self.calendar, now: { now })
        await appModel.bootstrap()
        try #require(appModel.state == .loaded)
        return RankingsViewModel(appModel: appModel)
    }

    private final class Server: Sendable {
        let client: APIClient
        let rankingsStatus = LockedBox(200)
        let slugs = LockedBox(["mosaic", "dogpatch"])
        let gate = LockedBox<DispatchSemaphore?>(nil)
        private let requests = LockedBox(0)

        var rankingsRequests: Int { requests.withValue { $0 } }

        init(host: String) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            client = APIClient(
                baseURL: URL(string: "https://\(host)")!,
                session: URLSession(configuration: configuration),
                accessToken: { "test-token" }
            )
            let (status, slugs, gate, requests) = (rankingsStatus, slugs, gate, requests)
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
                    let semaphore = gate.withValue { $0 }
                    let names = slugs.withValue { $0 }
                    requests.withValue { $0 += 1 }
                    semaphore?.wait()
                    let code = status.withValue { $0 }
                    return respond(code, code == 200 ? RankingsFixtures.body(slugs: names) : Data())
                default:
                    return respond(404, Data())
                }
            }
        }
    }
}
