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

    @Test func undecodableBodyThrowsADecodingError() async {
        StubURLProtocol.setHandler(forHost: host) { request in
            (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!,
                Data(#"{"value":"not-a-number"}"#.utf8)
            )
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let client = makeClient { "token" }

        do {
            _ = try await client.get("/changed-shape", as: Payload.self)
            Issue.record("Expected a decoding error")
        } catch let error as APIError {
            guard case .decoding = error else {
                Issue.record("Expected .decoding, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func gymsSendsAtAsAnISO8601InstantAndOmitsItOtherwise() async throws {
        let queries = LockedBox<[String?]>([])
        StubURLProtocol.setHandler(forHost: host) { request in
            queries.withValue { $0.append(request.url?.query) }
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!,
                Data(#"{"data":[]}"#.utf8)
            )
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let client = makeClient { "token" }
        // 2026-09-23 17:00:00 UTC
        _ = try await client.gyms(at: Date(timeIntervalSince1970: 1_790_182_800))
        _ = try await client.gyms()

        #expect(queries.withValue { $0 } == ["at=2026-09-23T17:00:00Z", nil])
    }

    @Test func meReadsTheProfileFromTheEnvelope() async throws {
        let requests = stub(
            status: 200,
            body: #"{"data":{"id":"7878e808-a48f-4649-8a65-3feb6029a591","display_name":"Alex"}}"#
        )
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let profile = try await makeClient { "token" }.me()

        #expect(profile.displayName == "Alex")
        #expect(requests.withValue { $0 } == [RecordedRequest(method: "GET", path: "/api/me")])
    }

    @Test func membershipsReadsSlugsAndTogglesWithEmpty204s() async throws {
        let requests = LockedBox<[RecordedRequest]>([])
        StubURLProtocol.setHandler(forHost: host) { request in
            requests.withValue { $0.append(RecordedRequest(request)) }
            let isList = request.httpMethod == "GET"
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: isList ? 200 : 204,
                    httpVersion: nil, headerFields: nil
                )!,
                isList ? Data(#"{"data":["dogpatch","mission"]}"#.utf8) : Data()
            )
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let client = makeClient { "token" }
        let slugs = try await client.memberships()
        try await client.addMembership(gymSlug: "dogpatch")
        try await client.removeMembership(gymSlug: "mission")

        #expect(slugs == ["dogpatch", "mission"])
        #expect(
            requests.withValue { $0 } == [
                RecordedRequest(method: "GET", path: "/api/me/memberships"),
                RecordedRequest(method: "POST", path: "/api/me/memberships/dogpatch"),
                RecordedRequest(method: "DELETE", path: "/api/me/memberships/mission"),
            ]
        )
    }

    @Test func unknownGymSlugIsABadStatusNotAConflict() async {
        _ = stub(status: 404, body: #"{"detail":"Gym not found"}"#)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        await #expect(throws: APIError.badStatus(404)) {
            try await makeClient { "token" }.addMembership(gymSlug: "nowhere")
        }
    }

    @Test func listAndGetLocationsUseTheLowercasedId() async throws {
        let id = try #require(UUID(uuidString: "D16878BE-C4BC-462F-8929-C464B6A5EFAD"))
        let requests = LockedBox<[RecordedRequest]>([])
        StubURLProtocol.setHandler(forHost: host) { request in
            requests.withValue { $0.append(RecordedRequest(request)) }
            let isList = request.url?.path == "/api/me/locations"
            let body = isList ? "{\"data\":[\(Self.homeJSON)]}" : "{\"data\":\(Self.homeJSON)}"
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!,
                Data(body.utf8)
            )
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let client = makeClient { "token" }
        let list = try await client.locations()
        let one = try await client.location(id: id)

        #expect(list == [one])
        #expect(one.kind == .home)
        #expect(
            requests.withValue { $0 } == [
                RecordedRequest(method: "GET", path: "/api/me/locations"),
                RecordedRequest(
                    method: "GET", path: "/api/me/locations/d16878be-c4bc-462f-8929-c464b6a5efad"
                ),
            ]
        )
    }

    @Test func createLocationPostsSnakeCaseJSONAndDecodesThe201() async throws {
        let requests = stub(status: 201, body: "{\"data\":\(Self.homeJSON)}")
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let created = try await makeClient { "token" }.createLocation(
            CreateSavedLocation(
                label: "Home", kind: .home, address: "Redwood City, CA",
                latitude: 37.4852, longitude: -122.2364, makeDefault: true
            )
        )

        let request = try #require(requests.withValue { $0.first })
        #expect(created.isDefault)
        #expect(request.method == "POST")
        #expect(request.path == "/api/me/locations")
        #expect(request.contentType == "application/json")
        #expect(
            try jsonObject(request.body) == [
                "label": "Home", "kind": "home", "address": "Redwood City, CA",
                "latitude": 37.4852, "longitude": -122.2364, "make_default": true,
            ]
        )
    }

    @Test func createLocationOmitsANilAddress() async throws {
        let requests = stub(status: 201, body: "{\"data\":\(Self.homeJSON)}")
        defer { StubURLProtocol.removeHandler(forHost: host) }

        _ = try await makeClient { "token" }.createLocation(
            CreateSavedLocation(label: "Home", kind: .home, latitude: 37.4852, longitude: -122.2364)
        )

        let body = try jsonObject(requests.withValue { $0.first?.body })
        #expect((body.allKeys as? [String])?.sorted() == ["kind", "label", "latitude", "longitude", "make_default"])
        #expect(body["make_default"] as? Bool == false)
    }

    @Test func updateLocationSendsOnlyTheFieldsThatAreSet() async throws {
        let id = UUID()
        let requests = stub(status: 200, body: "{\"data\":\(Self.homeJSON)}")
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let client = makeClient { "token" }
        _ = try await client.updateLocation(id: id, UpdateSavedLocation(label: "Casa"))
        _ = try await client.updateLocation(id: id, UpdateSavedLocation(address: .some(nil)))
        _ = try await client.updateLocation(
            id: id, UpdateSavedLocation(kind: .work, address: "SoMa", makeDefault: true)
        )

        let sent = requests.withValue { $0 }
        #expect(sent.map(\.method) == ["PATCH", "PATCH", "PATCH"])
        #expect(sent.allSatisfy { $0.path == "/api/me/locations/\(id.uuidString.lowercased())" })
        #expect(try jsonObject(sent[0].body) == ["label": "Casa"])
        #expect(try jsonObject(sent[1].body) == ["address": NSNull()])
        #expect(
            try jsonObject(sent[2].body) == ["kind": "work", "address": "SoMa", "make_default": true]
        )
    }

    @Test func deleteLocationAcceptsAnEmpty204() async throws {
        let id = UUID()
        let requests = stub(status: 204, body: "")
        defer { StubURLProtocol.removeHandler(forHost: host) }

        try await makeClient { "token" }.deleteLocation(id: id)

        #expect(
            requests.withValue { $0 } == [
                RecordedRequest(
                    method: "DELETE", path: "/api/me/locations/\(id.uuidString.lowercased())"
                )
            ]
        )
    }

    @Test func conflictCarriesTheDetailMessage() async {
        _ = stub(status: 409, body: #"{"detail":"You can't delete your only place"}"#)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        await #expect(throws: APIError.conflict("You can't delete your only place")) {
            try await makeClient { "token" }.deleteLocation(id: UUID())
        }
    }

    @Test func conflictOnACreateCarriesTheDetailMessage() async {
        _ = stub(status: 409, body: #"{"detail":"You already have a home"}"#)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        await #expect(throws: APIError.conflict("You already have a home")) {
            try await makeClient { "token" }.createLocation(
                CreateSavedLocation(label: "Home 2", kind: .home, latitude: 37, longitude: -122)
            )
        }
    }

    @Test func conflictWithoutADetailFallsBackToBadStatus() async {
        _ = stub(status: 409, body: "")
        defer { StubURLProtocol.removeHandler(forHost: host) }

        await #expect(throws: APIError.badStatus(409)) {
            try await makeClient { "token" }.deleteLocation(id: UUID())
        }
    }

    @Test func logoReturnsTheRawBytesAndETagWithTheBearerToken() async throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let sent = LockedBox<[URLRequest]>([])
        StubURLProtocol.setHandler(forHost: host) { request in
            sent.withValue { $0.append(request) }
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["ETag": #""abc123""#, "Content-Type": "image/png"]
                )!,
                bytes
            )
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let response = try await makeClient { "logo-token" }.logo(slug: "dogpatch")

        #expect(response == .image(bytes, etag: #""abc123""#))
        let request = try #require(sent.withValue { $0.first })
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/gyms/dogpatch/logo")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer logo-token")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func logoSendsIfNoneMatchAndTreatsA304AsNotModified() async throws {
        let ifNoneMatch = LockedBox<String?>(nil)
        StubURLProtocol.setHandler(forHost: host) { request in
            ifNoneMatch.withValue { $0 = request.value(forHTTPHeaderField: "If-None-Match") }
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: 304, httpVersion: nil,
                    headerFields: ["ETag": #""abc123""#]
                )!,
                Data()
            )
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let response = try await makeClient { "token" }
            .logo(slug: "dogpatch", ifNoneMatch: #""abc123""#)

        #expect(response == .notModified)
        #expect(ifNoneMatch.withValue { $0 } == #""abc123""#)
    }

    @Test func logoForAGymWithoutOneIsABadStatus404() async {
        _ = stub(status: 404, body: #"{"detail":"Gym logo not found"}"#)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        await #expect(throws: APIError.badStatus(404)) {
            try await makeClient { "token" }.logo(slug: "nowhere")
        }
    }

    @Test func jsonRequestsStillTreatA304AsAnError() async {
        _ = stub(status: 304, body: "")
        defer { StubURLProtocol.removeHandler(forHost: host) }

        await #expect(throws: APIError.badStatus(304)) {
            try await makeClient { "token" }.get("/unchanged", as: Payload.self)
        }
    }

    // MARK: - Helpers

    private static let homeJSON = """
        {"id":"d16878be-c4bc-462f-8929-c464b6a5efad","label":"Home","address":"Redwood City, CA",\
        "latitude":37.4852,"longitude":-122.2364,"is_default":true,"kind":"home"}
        """

    private struct RecordedRequest: Equatable, Sendable {
        let method: String
        let path: String
        var contentType: String? = nil
        var body: Data? = nil

        init(method: String, path: String) {
            self.method = method
            self.path = path
        }

        init(_ request: URLRequest) {
            method = request.httpMethod ?? ""
            path = request.url?.path ?? ""
            contentType = request.value(forHTTPHeaderField: "Content-Type")
            body = request.bodyData
        }

        /// Compares method and path only, so expectations needn't spell out bodies.
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.method == rhs.method && lhs.path == rhs.path
        }
    }

    /// Answers every request to `host` with `status` and `body`, recording each request.
    private func stub(status: Int, body: String) -> LockedBox<[RecordedRequest]> {
        let requests = LockedBox<[RecordedRequest]>([])
        StubURLProtocol.setHandler(forHost: host) { request in
            requests.withValue { $0.append(RecordedRequest(request)) }
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
                )!,
                Data(body.utf8)
            )
        }
        return requests
    }

    private func jsonObject(_ data: Data?) throws -> NSDictionary {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
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
