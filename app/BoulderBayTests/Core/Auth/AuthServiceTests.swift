import Foundation
import Supabase
import Testing

@testable import BoulderBay

@MainActor
@Suite(.serialized)
struct AuthServiceTests {
    private let host = "auth-service.test"

    @Test func restoresASavedSession() async throws {
        let storage = InMemoryAuthStorage()
        let session = makeSession(accessToken: "restored-token")
        try storage.store(
            key: "sb-auth-service-auth-token",
            value: AuthClient.Configuration.jsonEncoder.encode(session)
        )

        let service = makeService(storage: storage)
        await waitForRestoration(service)

        #expect(service.session?.accessToken == "restored-token")
        #expect(try await service.accessToken() == "restored-token")
    }

    @Test func restoresWithoutASavedSessionAsSignedOut() async {
        let service = makeService()
        await waitForRestoration(service)

        #expect(service.session == nil)
        #expect(!service.isRestoringSession)
    }

    @Test func signUpTrimsAndSendsDisplayNameMetadata() async throws {
        let capturedName = LockedBox<String?>(nil)
        let response = try AuthClient.Configuration.jsonEncoder.encode(
            makeSession(accessToken: "signup-token")
        )
        StubURLProtocol.setHandler(forHost: host) { request in
            let body = try Self.requestBody(request)
            let json = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let data = try #require(json["data"] as? [String: Any])
            capturedName.withValue { $0 = data["display_name"] as? String }
            return (Self.response(for: request, status: 200), response)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let service = makeService()
        let result = try await service.signUp(
            email: "climber@example.com",
            password: "correct-horse-battery-staple",
            displayName: "  Alex Rivera  "
        )

        #expect(result == .signedIn)
        #expect(service.session?.accessToken == "signup-token")
        #expect(capturedName.withValue { $0 } == "Alex Rivera")
    }

    @Test func signUpHandlesConfirmationRequired() async throws {
        let response = try AuthClient.Configuration.jsonEncoder.encode(makeUser())
        StubURLProtocol.setHandler(forHost: host) { request in
            (Self.response(for: request, status: 200), response)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let service = makeService()
        let result = try await service.signUp(
            email: "climber@example.com",
            password: "correct-horse-battery-staple",
            displayName: "Alex Rivera"
        )

        #expect(result == .confirmationRequired)
        #expect(service.session == nil)
    }

    @Test(
        arguments: [
            "",
            "   ",
            String(repeating: "a", count: 81),
            String(repeating: "e\u{301}", count: 41),
            "Alex2",
            "Alex-Rivera",
            "O'Rivera",
            "José",
            "Alex\tRivera",
            "Alex 🧗",
        ]
    )
    func signUpRejectsInvalidDisplayNames(displayName: String) async {
        let service = makeService()

        do {
            _ = try await service.signUp(
                email: "climber@example.com",
                password: "correct-horse-battery-staple",
                displayName: displayName
            )
            Issue.record("Expected display-name validation to fail")
        } catch let error as AuthServiceError {
            #expect(error == .invalidDisplayName)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func signInAndLocalSignOutUpdateTheSession() async throws {
        let scopes = LockedBox<[String]>([])
        let sessionData = try AuthClient.Configuration.jsonEncoder.encode(
            makeSession(accessToken: "signin-token")
        )
        StubURLProtocol.setHandler(forHost: host) { request in
            if request.url?.path.hasSuffix("/token") == true {
                return (Self.response(for: request, status: 200), sessionData)
            }
            if request.url?.path.hasSuffix("/logout") == true {
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                let scope = components?.queryItems?.first(where: { $0.name == "scope" })?.value
                scopes.withValue { $0.append(scope ?? "") }
                return (Self.response(for: request, status: 204), Data())
            }
            throw URLError(.unsupportedURL)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let service = makeService()
        try await service.signIn(email: "climber@example.com", password: "password")
        #expect(service.session?.accessToken == "signin-token")

        try await service.signOut()
        #expect(service.session == nil)
        #expect(scopes.withValue { $0 } == ["local"])
    }

    private func makeService(storage: InMemoryAuthStorage = InMemoryAuthStorage()) -> AuthService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let options = SupabaseClientOptions(
            auth: .init(storage: storage),
            global: .init(session: URLSession(configuration: configuration))
        )
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://\(host)")!,
            supabaseKey: "test-key",
            options: options
        )
        return AuthService(client: client)
    }

    private func makeSession(accessToken: String) -> Session {
        Session(
            accessToken: accessToken,
            tokenType: "bearer",
            expiresIn: 3_600,
            expiresAt: Date.now.addingTimeInterval(3_600).timeIntervalSince1970,
            refreshToken: "refresh-token",
            user: makeUser()
        )
    }

    private func makeUser() -> User {
        User(
            id: UUID(uuidString: "7878e808-a48f-4649-8a65-3feb6029a591")!,
            appMetadata: [:],
            userMetadata: ["display_name": .string("Alex Rivera")],
            aud: "authenticated",
            email: "climber@example.com",
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func waitForRestoration(_ service: AuthService) async {
        for _ in 0..<100 {
            if !service.isRestoringSession { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Session restoration did not finish")
    }

    nonisolated private static func response(
        for request: URLRequest, status: Int
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
    }

    nonisolated private static func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var body = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4_096)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            body.append(buffer, count: count)
        }
        return body
    }
}
