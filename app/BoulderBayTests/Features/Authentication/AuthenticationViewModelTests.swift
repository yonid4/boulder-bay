import Foundation
import Supabase
import Testing

@testable import BoulderBay

@MainActor
@Suite(.serialized)
struct AuthenticationViewModelTests {
    private let host = "auth-view-model.test"

    @Test func startsInSignInModeWithMockupCopy() {
        let (model, _) = makeModel()

        #expect(model.mode == .signIn)
        #expect(model.title == "Welcome back")
        #expect(model.submitLabel == "Sign in")
        #expect(model.switchModeLabel == "New here? Create an account")
    }

    @Test func toggleModeSwitchesCopyAndClearsMessages() async {
        StubURLProtocol.setHandler(forHost: host) { request in
            (Self.response(for: request, status: 400), Self.invalidCredentials)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let (model, _) = makeModel()
        model.email = "climber@example.com"
        model.password = "wrong"
        await model.submit()
        #expect(model.errorMessage != nil)

        model.toggleMode()

        #expect(model.mode == .signUp)
        #expect(model.title == "Create account")
        #expect(model.submitLabel == "Create account")
        #expect(model.switchModeLabel == "Already have an account? Sign in")
        #expect(model.errorMessage == nil)
    }

    @Test func canSubmitRequiresNameOnlyWhenSigningUp() {
        let (model, _) = makeModel()
        #expect(!model.canSubmit)

        model.email = "climber@example.com"
        model.password = "correct-horse-battery-staple"
        #expect(model.canSubmit)

        model.toggleMode()
        #expect(!model.canSubmit)

        model.displayName = "Alex Rivera"
        #expect(model.canSubmit)
    }

    @Test func signInSuccessSetsTheSession() async throws {
        let sessionData = try AuthClient.Configuration.jsonEncoder.encode(
            makeSession(accessToken: "signin-token")
        )
        StubURLProtocol.setHandler(forHost: host) { request in
            (Self.response(for: request, status: 200), sessionData)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let (model, service) = makeModel()
        model.email = "climber@example.com"
        model.password = "correct-horse-battery-staple"
        await model.submit()

        #expect(service.session?.accessToken == "signin-token")
        #expect(model.errorMessage == nil)
        #expect(!model.isSubmitting)
        #expect(model.email.isEmpty)
        #expect(model.password.isEmpty)
    }

    @Test func signInFailureShowsTheServerMessage() async {
        StubURLProtocol.setHandler(forHost: host) { request in
            (Self.response(for: request, status: 400), Self.invalidCredentials)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let (model, service) = makeModel()
        model.email = "climber@example.com"
        model.password = "wrong"
        await model.submit()

        #expect(service.session == nil)
        #expect(model.errorMessage == "Invalid login credentials")
        #expect(!model.isSubmitting)
    }

    @Test func signUpWithoutASessionAwaitsEmailConfirmation() async throws {
        let userData = try AuthClient.Configuration.jsonEncoder.encode(makeUser())
        StubURLProtocol.setHandler(forHost: host) { request in
            (Self.response(for: request, status: 200), userData)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let (model, service) = makeModel()
        model.toggleMode()
        model.displayName = "Alex Rivera"
        model.email = "climber@example.com"
        model.password = "correct-horse-battery-staple"
        await model.submit()

        #expect(service.session == nil)
        #expect(model.isAwaitingEmailConfirmation)
        #expect(model.errorMessage == nil)
        #expect(!model.isSubmitting)
        #expect(model.email == "climber@example.com")
        #expect(model.password.isEmpty)
    }

    @Test func signUpWithAnInvalidNameFailsBeforeAnyRequest() async {
        let requestCount = LockedBox(0)
        StubURLProtocol.setHandler(forHost: host) { request in
            requestCount.withValue { $0 += 1 }
            return (Self.response(for: request, status: 500), Data())
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let (model, _) = makeModel()
        model.toggleMode()
        model.displayName = "Alex2"
        model.email = "climber@example.com"
        model.password = "correct-horse-battery-staple"
        await model.submit()

        #expect(model.errorMessage == "Name must be 1–80 letters and spaces.")
        #expect(requestCount.withValue { $0 } == 0)
        #expect(!model.isAwaitingEmailConfirmation)
    }

    private func makeModel() -> (AuthenticationViewModel, AuthService) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let options = SupabaseClientOptions(
            auth: .init(storage: InMemoryAuthStorage()),
            global: .init(session: URLSession(configuration: configuration))
        )
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://\(host)")!,
            supabaseKey: "test-key",
            options: options
        )
        let service = AuthService(client: client)
        return (AuthenticationViewModel(authService: service), service)
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

    nonisolated private static let invalidCredentials = Data(
        #"{"code":"invalid_credentials","message":"Invalid login credentials"}"#.utf8
    )

    nonisolated private static func response(
        for request: URLRequest, status: Int
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
    }
}
