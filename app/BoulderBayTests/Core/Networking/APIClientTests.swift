import Foundation
import Testing

@testable import BoulderBay

@Suite(.serialized)
struct APIClientTests {
    private struct Payload: Decodable, Sendable {
        let value: Int
    }

    private enum TokenError: Error {
        case unavailable
    }

    private let host = "api-client.test"

    @Test func attachesTheLatestAccessTokenToEveryRequest() async throws {
        let headers = LockedBox<[String]>([])
        StubURLProtocol.setHandler(forHost: host) { request in
            headers.withValue { $0.append(request.value(forHTTPHeaderField: "Authorization") ?? "") }
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!,
                Data(#"{"value":1}"#.utf8)
            )
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let tokens = LockedBox(["first-token", "second-token"])
        let client = makeClient {
            tokens.withValue { $0.removeFirst() }
        }

        _ = try await client.get("/first", as: Payload.self)
        _ = try await client.get("/second", as: Payload.self)

        #expect(headers.withValue { $0 } == ["Bearer first-token", "Bearer second-token"])
        #expect(tokens.withValue { $0.isEmpty })
    }

    @Test func tokenFailurePreventsTheNetworkRequest() async {
        let requestCount = LockedBox(0)
        StubURLProtocol.setHandler(forHost: host) { request in
            requestCount.withValue { $0 += 1 }
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!,
                Data(#"{"value":1}"#.utf8)
            )
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let client = makeClient { throw TokenError.unavailable }

        do {
            _ = try await client.get("/never-sent", as: Payload.self)
            Issue.record("Expected token lookup to fail")
        } catch is TokenError {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(requestCount.withValue { $0 } == 0)
    }

    @Test func unauthorizedResponseIsNotRetried() async {
        let requestCount = LockedBox(0)
        let tokenCount = LockedBox(0)
        StubURLProtocol.setHandler(forHost: host) { request in
            requestCount.withValue { $0 += 1 }
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
                )!,
                Data()
            )
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let client = makeClient {
            tokenCount.withValue { $0 += 1 }
            return "current-token"
        }

        do {
            _ = try await client.get("/protected", as: Payload.self)
            Issue.record("Expected a 401 error")
        } catch let error as APIError {
            #expect(error == .badStatus(401))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(requestCount.withValue { $0 } == 1)
        #expect(tokenCount.withValue { $0 } == 1)
    }

    private func makeClient(
        accessToken: @escaping @Sendable () async throws -> String
    ) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(
            baseURL: URL(string: "https://\(host)")!,
            session: URLSession(configuration: configuration),
            accessToken: accessToken
        )
    }
}
