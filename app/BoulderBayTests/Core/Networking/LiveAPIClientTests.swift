import Foundation
import Testing

@testable import BoulderBay

/// `StubURLProtocol` keeps one process-wide handler, so these run one at a time.
@Suite(.serialized)
struct LiveAPIClientTests {
    private func makeClient(token: String? = "jwt-123") -> LiveAPIClient {
        LiveAPIClient(
            baseURL: URL(string: "http://api.test")!,
            session: StubURLProtocol.session(),
            tokenProvider: { token }
        )
    }

    @Test func getUnwrapsTheEnvelopeAndSendsTheBearer() async throws {
        StubURLProtocol.respond(status: 200, body: try Fixture.data("gyms"))

        let gyms = try await makeClient().gyms()

        #expect(gyms.map(\.slug) == ["dogpatch", "mosaic"])
        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.url?.absoluteString == "http://api.test/api/gyms")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-123")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func signedOutRequestsCarryNoAuthorizationHeader() async throws {
        StubURLProtocol.respond(status: 200, body: try Fixture.data("me"))

        _ = try await makeClient(token: nil).me()

        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func rankingsEncodesLocationAndOptionalAt() async throws {
        StubURLProtocol.respond(status: 200, body: try Fixture.data("rankings"))
        let id = UUID(uuidString: "6F1D2C3E-4B5A-4C6D-8E7F-90A1B2C3D4E5")!
        let at = try #require(ISO8601DateFormatter().date(from: "2026-09-09T00:00:00Z"))

        _ = try await makeClient().rankings(locationID: id, at: at)
        _ = try await makeClient().rankings(locationID: id, at: nil)

        let urls = StubURLProtocol.recordedRequests.compactMap(\.url?.absoluteString)
        #expect(urls[0] == "http://api.test/api/rankings?location_id=6f1d2c3e-4b5a-4c6d-8e7f-90a1b2c3d4e5&at=2026-09-09T00:00:00Z")
        #expect(urls[1] == "http://api.test/api/rankings?location_id=6f1d2c3e-4b5a-4c6d-8e7f-90a1b2c3d4e5")
    }

    @Test func putMembershipsSendsTheWholeSetAsJSON() async throws {
        StubURLProtocol.respond(status: 200, body: try Fixture.data("memberships"))

        let stored = try await makeClient().updateMemberships(["mv-sf", "mosaic"])

        #expect(stored.count == 4)
        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.bodyBytes)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: [String]])
        #expect(json == ["gym_slugs": ["mv-sf", "mosaic"]])
    }

    @Test func deleteTargetsTheLocationIdAndIgnoresTheBody() async throws {
        StubURLProtocol.respond(status: 204)
        let id = UUID(uuidString: "6F1D2C3E-4B5A-4C6D-8E7F-90A1B2C3D4E5")!

        try await makeClient().deleteLocation(id: id)

        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/me/locations/6f1d2c3e-4b5a-4c6d-8e7f-90a1b2c3d4e5")
    }

    @Test func statusCodesMapToAPIErrors() async throws {
        StubURLProtocol.respond(status: 401)
        await #expect(throws: APIError.unauthorized) {
            try await makeClient().gyms()
        }

        StubURLProtocol.respond(status: 503)
        await #expect(throws: APIError.badStatus(503)) {
            try await makeClient().gyms()
        }
    }

    @Test func malformedBodyIsADecodingError() async throws {
        StubURLProtocol.respond(status: 200, body: Data("{\"data\": 42}".utf8))

        await #expect(throws: APIError.self) {
            try await makeClient().gyms()
        }
    }

    @Test func transportFailureIsSurfacedAsTransport() async throws {
        StubURLProtocol.respond { _ in throw URLError(.notConnectedToInternet) }

        do {
            _ = try await makeClient().gyms()
            Issue.record("expected a transport error")
        } catch let error as APIError {
            guard case .transport = error else {
                Issue.record("expected .transport, got \(error)")
                return
            }
        }
    }
}
