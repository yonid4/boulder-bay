import Foundation
import Observation

/// The composition root: one auth service, one API client, the four stores, built once
/// and handed to every screen through the environment.
///
/// It also owns the launch sequence. `phase` is what `RootView` switches on: the auth
/// session alone isn't enough, because a signed-in user still needs the mock account
/// swapped in and their locations and memberships fetched before the gate can decide
/// between onboarding and the app shell.
@MainActor
@Observable
final class AppContainer {
    enum Phase: Equatable {
        /// Reading the persisted session.
        case resolving
        case signedOut
        case awaitingEmailConfirmation(email: String)
        /// Signed in; fetching what the gate needs.
        case preparing
        case ready(AuthUser)
    }

    let auth: any AuthService
    let api: any APIClient
    let gyms: GymStore
    let locations: LocationStore
    let memberships: MembershipStore
    let rankings: RankingStore

    private(set) var phase: Phase = .resolving
    /// The mock client, when that is what `api` is, so accounts can be swapped on sign-in.
    private let mock: MockAPIClient?
    private var started = false

    init(auth: any AuthService, api: any APIClient, now: @escaping @Sendable () -> Date = { .now }) {
        self.auth = auth
        self.api = api
        mock = api as? MockAPIClient
        gyms = GymStore(api: api)
        locations = LocationStore(api: api)
        memberships = MembershipStore(api: api)
        rankings = RankingStore(api: api, locations: locations, now: now)
    }

    /// What the app runs on, from `AppConfig`: Supabase auth when the xcconfig has keys,
    /// the mock otherwise; the mock API in Debug unless overridden.
    static func live() -> AppContainer {
        let auth: any AuthService = SupabaseAuthService() ?? MockAuthService()
        let api: any APIClient = AppConfig.useMockAPI
            ? MockAPIClient(latency: .milliseconds(250))
            : LiveAPIClient(tokenProvider: { [auth] in await auth.accessToken() })
        return AppContainer(auth: auth, api: api)
    }

    var isUsingMockAPI: Bool { mock != nil }

    /// Starts auth and follows the session for the life of the app. Idempotent.
    func start() async {
        guard !started else { return }
        started = true
        observeSession()
        await auth.start()
        await handleSessionChange()
    }

    // MARK: Session

    private func observeSession() {
        withObservationTracking {
            _ = auth.session.state
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await handleSessionChange()
                observeSession()
            }
        }
    }

    private func handleSessionChange() async {
        switch auth.session.state {
        case .resolving:
            phase = .resolving
        case .signedOut:
            locations.reset()
            memberships.reset()
            rankings.reset()
            phase = .signedOut
        case .awaitingEmailConfirmation(let email):
            phase = .awaitingEmailConfirmation(email: email)
        case .signedIn(let user):
            if case .ready(let current) = phase, current.id == user.id { return }
            phase = .preparing
            await prepare(for: user)
            // The user may have signed out while we were fetching.
            guard auth.session.user?.id == user.id else { return }
            phase = .ready(user)
        }
    }

    private func prepare(for user: AuthUser) async {
        if let mock {
            let profile = UserProfile(id: user.id, email: user.email, displayName: user.displayName)
            await mock.use(account: user.isNewAccount ? .fresh(profile: profile) : .seeded(profile: profile))
        }
        async let gymsLoad: () = gyms.loadIfNeeded()
        async let locationsLoad: () = locations.load()
        async let membershipsLoad: () = memberships.load()
        _ = await (gymsLoad, locationsLoad, membershipsLoad)
        rankings.markStale()
    }

    func signOut() async {
        try? await auth.signOut()
    }
}

#if DEBUG
extension AppContainer {
    /// A container over the mock API and a signed-in mock user, frozen at the mockup's
    /// demo clock, with the stores already loaded — what `#Preview`s want.
    static func preview(fresh: Bool = false) -> AppContainer {
        let container = AppContainer(
            auth: MockAuthService.signedIn(as: .preview),
            api: PreviewData.api(fresh: fresh),
            now: { PreviewData.now }
        )
        Task { await container.start() }
        return container
    }
}
#endif
