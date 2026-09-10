import Foundation
import Testing

@testable import BoulderBay

@MainActor
struct MockAuthServiceTests {
    private func makeDefaults() -> UserDefaults {
        let name = "MockAuthServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func startWithNothingPersistedIsSignedOut() async {
        let service = MockAuthService(defaults: makeDefaults())
        #expect(service.session.state == .resolving)

        await service.start()

        #expect(service.session.state == .signedOut)
        #expect(await service.accessToken() == nil)
    }

    @Test func signInAcceptsAnyEmailWithASixCharacterPassword() async throws {
        let service = MockAuthService(defaults: makeDefaults())
        await service.start()

        try await service.signIn(email: " Alex.Chen@Example.com ", password: "secret1")

        let user = try #require(service.session.user)
        #expect(user.email == "alex.chen@example.com")
        #expect(user.displayName == "Alex Chen")
        #expect(!user.isNewAccount)
        #expect(await service.accessToken() == "mock-access-token")
    }

    @Test func signInRejectsBadInput() async {
        let service = MockAuthService(defaults: makeDefaults())
        await service.start()

        await #expect(throws: AuthServiceError.invalidCredentials) {
            try await service.signIn(email: "not-an-email", password: "secret1")
        }
        await #expect(throws: AuthServiceError.invalidCredentials) {
            try await service.signIn(email: "a@b.co", password: "short")
        }
        #expect(service.session.state == .signedOut)
    }

    @Test func signUpMarksTheAccountNewAndKeepsTheName() async throws {
        let service = MockAuthService(defaults: makeDefaults())
        await service.start()

        try await service.signUp(name: "  Sam Lee ", email: "sam@lee.io", password: "climb-on")

        let user = try #require(service.session.user)
        #expect(user.isNewAccount)
        #expect(user.displayName == "Sam Lee")
    }

    @Test func signUpRejectsAWeakPassword() async {
        let service = MockAuthService(defaults: makeDefaults())
        await service.start()

        await #expect(throws: AuthServiceError.self) {
            try await service.signUp(name: "", email: "sam@lee.io", password: "abc")
        }
    }

    @Test func sessionSurvivesARelaunchUntilSignOut() async throws {
        let defaults = makeDefaults()
        let first = MockAuthService(defaults: defaults)
        await first.start()
        try await first.signIn(email: "sam@lee.io", password: "climb-on")
        let id = try #require(first.session.user?.id)

        let relaunched = MockAuthService(defaults: defaults)
        await relaunched.start()
        #expect(relaunched.session.user?.id == id)
        #expect(relaunched.session.user?.isNewAccount == false)

        try await relaunched.signOut()
        #expect(relaunched.session.state == .signedOut)

        let again = MockAuthService(defaults: defaults)
        await again.start()
        #expect(again.session.state == .signedOut)
    }

    @Test func sameEmailAlwaysGetsTheSameId() async throws {
        let a = MockAuthService(defaults: makeDefaults())
        let b = MockAuthService(defaults: makeDefaults())
        await a.start()
        await b.start()

        try await a.signIn(email: "sam@lee.io", password: "climb-on")
        try await b.signUp(name: "Sam", email: "SAM@lee.io", password: "climb-on")

        #expect(a.session.user?.id == b.session.user?.id)
    }
}
