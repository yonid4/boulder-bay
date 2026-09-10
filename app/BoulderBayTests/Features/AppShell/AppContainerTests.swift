import Foundation
import Testing

@testable import BoulderBay

@MainActor
struct AppContainerTests {
    private func makeContainer() -> (MockAuthService, AppContainer) {
        let name = "AppContainerTests-\(UUID().uuidString)"
        let auth = MockAuthService(defaults: UserDefaults(suiteName: name)!)
        let container = AppContainer(auth: auth, api: MockAPIClient(), now: { wednesday5pm })
        return (auth, container)
    }

    @Test func startsSignedOutWhenNothingIsPersisted() async {
        let (_, container) = makeContainer()
        #expect(container.phase == .resolving)

        await container.start()

        #expect(container.phase == .signedOut)
        #expect(container.isUsingMockAPI)
    }

    @Test func signInPreparesASeededAccount() async throws {
        let (auth, container) = makeContainer()
        await container.start()

        try await auth.signIn(email: "alex@example.com", password: "climb-on")
        await waitUntil { if case .ready = container.phase { true } else { false } }

        let user = try #require(auth.session.user)
        #expect(container.phase == .ready(user))
        #expect(container.locations.current?.label == "Home")
        #expect(container.memberships.slugs.count == 4)
        #expect(container.gyms.gyms.count == 16)
        #expect(try await container.api.me().email == "alex@example.com")
    }

    @Test func signUpPreparesAFreshAccount() async throws {
        let (auth, container) = makeContainer()
        await container.start()

        try await auth.signUp(name: "Sam", email: "sam@lee.io", password: "climb-on")
        await waitUntil { if case .ready = container.phase { true } else { false } }

        #expect(container.locations.hasLoaded)
        #expect(container.locations.current == nil)
        #expect(container.memberships.slugs.isEmpty)
        #expect(try await container.api.me().displayName == "Sam")
    }

    @Test func signOutResetsTheStores() async throws {
        let (auth, container) = makeContainer()
        await container.start()
        try await auth.signIn(email: "alex@example.com", password: "climb-on")
        await waitUntil { if case .ready = container.phase { true } else { false } }

        await container.signOut()
        await waitUntil { container.phase == .signedOut }

        #expect(container.locations.locations.isEmpty)
        #expect(container.memberships.slugs.isEmpty)
        #expect(container.rankings.rankings == nil)
    }
}

/// Polls a main-actor condition, since the container reacts to session changes through
/// observation rather than a direct call.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
