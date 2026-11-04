import Foundation
import SwiftUI
import Testing
import UIKit

@testable import BoulderBay

@MainActor
@Suite(.serialized)
struct GymDetailViewModelTests {
    private let host = "gym-detail-view-model.test"

    @Test func loadPublishesTheDetail() async {
        stub { _ in (200, GymDetailFixtures.fullPayload) }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        #expect(model.state == .loading)

        await model.load()

        #expect(model.state == .loaded(GymDetailFixtures.full))
    }

    @Test func loadAsksForTheSelectedHourLikeTheMap() async throws {
        let urls = stub { _ in (200, GymDetailFixtures.fullPayload) }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let appModel = makeAppModel()
        appModel.selectedHour = 19
        let model = makeModel(appModel: appModel)
        await model.load()

        let url = try #require(urls.withValue { $0.first })
        #expect(url.path == "/api/gyms/dogpatch")
        let at = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "at" }?.value
        )
        #expect(at == appModel.date(forHour: 19).formatted(.iso8601))
    }

    @Test func aServerErrorIsFailedWithItsMessage() async {
        stub { _ in (500, Data()) }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.load()

        #expect(model.state == .failed("The server returned an error (500)."))
    }

    @Test func aMissingGymSaysSo() async {
        stub { _ in (404, Data(#"{"detail": "Gym not found"}"#.utf8)) }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.load()

        #expect(model.state == .failed("This gym is no longer available."))
    }

    @Test func retryingAfterAFailureRecovers() async {
        stub { count in
            count == 1 ? (500, Data()) : (200, GymDetailFixtures.fullPayload)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.load()
        await model.load()

        #expect(model.state == .loaded(GymDetailFixtures.full))
    }

    @Test func aFailedRefreshKeepsTheLastGoodDetail() async {
        stub { count in
            count == 1 ? (200, GymDetailFixtures.fullPayload) : (500, Data())
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.load()
        await model.load()

        #expect(model.state == .loaded(GymDetailFixtures.full))
    }

    @Test func aRefreshReplacesTheDetailWithoutGoingThroughLoading() async {
        stub { count in
            (200, count == 1 ? GymDetailFixtures.fullPayload : GymDetailFixtures.sparsePayload)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let gate = TokenGate(stallingCall: 2)
        let model = makeModel(gate: gate)
        await model.load()

        let refresh = Task { await model.load() }
        await gate.waitUntilStalled()
        #expect(model.state == .loaded(GymDetailFixtures.full))

        await gate.open()
        await refresh.value
        #expect(model.state == .loaded(GymDetailFixtures.sparse))
    }

    @Test func aStaleResponseIsIgnoredOnceANewerLoadHasStarted() async {
        // The first load is held back, so the newer load's request reaches the server first.
        stub { count in
            (200, count == 1 ? GymDetailFixtures.fullPayload : GymDetailFixtures.sparsePayload)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let gate = TokenGate(stallingCall: 1)
        let model = makeModel(gate: gate)
        let stale = Task { await model.load() }
        await gate.waitUntilStalled()

        await model.load()
        #expect(model.state == .loaded(GymDetailFixtures.full))

        await gate.open()
        await stale.value
        #expect(model.state == .loaded(GymDetailFixtures.full))
    }

    @Test func aStaleFailureIsIgnoredToo() async {
        stub { count in
            count == 1 ? (200, GymDetailFixtures.fullPayload) : (500, Data())
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let gate = TokenGate(stallingCall: 1)
        let model = makeModel(gate: gate)
        let stale = Task { await model.load() }
        await gate.waitUntilStalled()

        await model.load()
        await gate.open()
        await stale.value

        #expect(model.state == .loaded(GymDetailFixtures.full))
    }

    @Test func aCancelledLoadDoesNotReportAFailure() async {
        stub { _ in throw URLError(.cancelled) }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let gate = TokenGate(stallingCall: 1)
        let model = makeModel(gate: gate)
        let load = Task { await model.load() }
        await gate.waitUntilStalled()
        load.cancel()
        await gate.open()
        await load.value

        #expect(model.state == .loading)
    }

    @Test func theViewRefetchesWhenAPollBumpsLiveRefreshCount() async throws {
        let urls = stub { _ in (200, GymDetailFixtures.fullPayload) }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let (pings, continuation) = AsyncStream<Void>.makeStream()
        let appModel = makeAppModel(pollPings: { pings })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = UIHostingController(
            rootView: GymDetailView(slug: "dogpatch", apiClient: makeClient(), appModel: appModel)
        )
        window.isHidden = false
        defer { window.isHidden = true }
        let listener = Task { await appModel.listenForPolls() }
        defer { listener.cancel() }

        try await waitUntil { urls.withValue { $0.count } == 1 }

        continuation.yield()
        try await waitUntil { appModel.liveRefreshCount == 1 }
        try await waitUntil { urls.withValue { $0.count } == 2 }
    }

    // MARK: Helpers

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Timed out waiting")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Stubs the host, passing the handler the 1-based request count. Returns the URLs asked for.
    @discardableResult
    private func stub(
        _ handler: @escaping @Sendable (Int) throws -> (Int, Data)
    ) -> LockedBox<[URL]> {
        let urls = LockedBox<[URL]>([])
        StubURLProtocol.setHandler(forHost: host) { request in
            let count = urls.withValue { urls -> Int in
                urls.append(request.url!)
                return urls.count
            }
            let (status, body) = try handler(count)
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
                )!,
                body
            )
        }
        return urls
    }

    private func makeClient(gate: TokenGate? = nil) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(
            baseURL: URL(string: "https://\(host)")!,
            session: URLSession(configuration: configuration),
            accessToken: {
                await gate?.passThrough()
                return "token"
            }
        )
    }

    private func makeAppModel(
        pollPings: @escaping @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } }
    ) -> AppModel {
        AppModel(
            apiClient: makeClient(),
            pollPings: pollPings,
            refreshDelay: { .zero },
            sleep: { _ in }
        )
    }

    private func makeModel(
        appModel: AppModel? = nil, gate: TokenGate? = nil
    ) -> GymDetailViewModel {
        GymDetailViewModel(
            slug: "dogpatch", apiClient: makeClient(gate: gate), appModel: appModel ?? makeAppModel()
        )
    }
}

/// Holds one load back, before its request goes out, until the test says so. It waits on the
/// access token rather than in the stub: blocking inside `URLProtocol` stalls every other
/// stubbed request, since they share a loading thread.
private actor TokenGate {
    private let stallingCall: Int
    private var calls = 0
    private var release: CheckedContinuation<Void, Never>?
    private var stallWaiter: CheckedContinuation<Void, Never>?

    init(stallingCall: Int) {
        self.stallingCall = stallingCall
    }

    /// Called from the client's `accessToken`.
    func passThrough() async {
        calls += 1
        guard calls == stallingCall else { return }
        await withCheckedContinuation { continuation in
            release = continuation
            stallWaiter?.resume()
            stallWaiter = nil
        }
    }

    func waitUntilStalled() async {
        guard release == nil else { return }
        await withCheckedContinuation { stallWaiter = $0 }
    }

    func open() {
        release?.resume()
        release = nil
    }
}
