import Foundation
import Testing
import UIKit

@testable import BoulderBay

@Suite(.serialized)
struct LogoStoreTests {
    private let host = "logo-store.test"

    @Test func concurrentRequestsForOneSlugShareOneFetch() async throws {
        let requests = stub(status: 200, body: Self.png, delay: 0.2)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let store = makeStore()
        let images = await withTaskGroup(of: UIImage?.self) { group in
            for _ in 0..<5 {
                group.addTask { await store.logo(for: "dogpatch") }
            }
            return await group.reduce(into: [UIImage?]()) { $0.append($1) }
        }

        #expect(images.count == 5)
        #expect(images.allSatisfy { $0 != nil })
        #expect(requests.withValue { $0.count } == 1)
    }

    @Test func aLoadedLogoIsServedFromMemoryForTheRestOfTheLaunch() async throws {
        let requests = stub(status: 200, body: Self.png)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let store = makeStore()
        let first = await store.logo(for: "dogpatch")
        let second = await store.logo(for: "dogpatch")

        #expect(first != nil)
        #expect(first === second)
        #expect(requests.withValue { $0.count } == 1)
    }

    @Test func eachSlugIsFetchedFromItsOwnRouteWithTheBearerToken() async throws {
        let requests = stub(status: 200, body: Self.png)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let store = makeStore(token: "store-token")
        _ = await store.logo(for: "dogpatch")
        _ = await store.logo(for: "mission")

        let sent = requests.withValue { $0 }
        #expect(sent.map(\.url?.path) == ["/api/gyms/dogpatch/logo", "/api/gyms/mission/logo"])
        #expect(sent.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer store-token" })
    }

    @Test func a404MeansNoLogoAndIsNotAskedAgain() async {
        let requests = stub(status: 404, body: Data(#"{"detail":"Gym logo not found"}"#.utf8))
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let store = makeStore()
        let first = await store.logo(for: "nowhere")
        let second = await store.logo(for: "nowhere")

        #expect(first == nil)
        #expect(second == nil)
        #expect(requests.withValue { $0.count } == 1)
    }

    @Test func bytesThatAreNotAnImageMeanNoLogo() async {
        let requests = stub(status: 200, body: Data("not a png".utf8))
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let store = makeStore()
        #expect(await store.logo(for: "dogpatch") == nil)
        #expect(await store.logo(for: "dogpatch") == nil)
        #expect(requests.withValue { $0.count } == 1)
    }

    @Test func aTransientFailureIsRetriedOnTheNextRequest() async {
        let statuses = LockedBox([500, 200])
        let requestCount = LockedBox(0)
        StubURLProtocol.setHandler(forHost: host) { request in
            requestCount.withValue { $0 += 1 }
            let status = statuses.withValue { $0.removeFirst() }
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
                )!,
                status == 200 ? Self.png : Data()
            )
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let store = makeStore()
        let failed = await store.logo(for: "dogpatch")
        let retried = await store.logo(for: "dogpatch")

        #expect(failed == nil)
        #expect(retried != nil)
        #expect(requestCount.withValue { $0 } == 2)
    }

    @Test func theStoresOwnSessionWritesNothingToACache() {
        let configuration = LogoStore.makeSession().configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    // MARK: - Helpers

    /// A 1×1 PNG, enough for `UIImage(data:)` to decode.
    private static let png: Data = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        .pngData { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }

    /// Answers every request to `host` with `status` and `body` after `delay` seconds,
    /// recording each request.
    private func stub(status: Int, body: Data, delay: TimeInterval = 0) -> LockedBox<[URLRequest]> {
        let requests = LockedBox<[URLRequest]>([])
        StubURLProtocol.setHandler(forHost: host) { request in
            requests.withValue { $0.append(request) }
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
                )!,
                body
            )
        }
        return requests
    }

    private func makeStore(token: String = "token") -> LogoStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return LogoStore(
            client: APIClient(
                baseURL: URL(string: "https://\(host)")!,
                session: URLSession(configuration: configuration),
                accessToken: { token }
            )
        )
    }
}
