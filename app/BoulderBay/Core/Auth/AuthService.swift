import Foundation
import Observation

/// The signed-in account as the app sees it. `isNewAccount` is true only for the launch
/// in which the account was created, so the composition root can seed a fresh mock
/// account instead of a returning one.
struct AuthUser: Hashable, Sendable {
    let id: UUID
    let email: String
    let displayName: String?
    var isNewAccount = false
}

enum AuthState: Hashable, Sendable {
    /// Before the persisted session (if any) has been read. `RootView` shows a spinner.
    case resolving
    case signedOut
    /// Sign-up succeeded but Supabase requires the email link before a session exists.
    case awaitingEmailConfirmation(email: String)
    case signedIn(AuthUser)

    var user: AuthUser? {
        if case .signedIn(let user) = self { return user }
        return nil
    }
}

/// The one app-wide auth state, observed by `RootView` and the side menu. Owned by an
/// `AuthService`, which is the only thing that writes to it.
@MainActor
@Observable
final class AuthSession {
    private(set) var state: AuthState

    init(state: AuthState = .resolving) {
        self.state = state
    }

    var user: AuthUser? { state.user }
    var isSignedIn: Bool { user != nil }

    func transition(to state: AuthState) {
        self.state = state
    }
}

/// Sign-up / sign-in / sign-out plus the access token the API layer attaches to every
/// request. `SupabaseAuthService` is the real thing; `MockAuthService` is used when the
/// project has no Supabase keys, and in previews and tests.
///
/// Main-actor bound because its observable session is, and every caller is a view model.
@MainActor
protocol AuthService: AnyObject {
    var session: AuthSession { get }

    /// Restores a persisted session and starts listening for changes. Idempotent.
    func start() async
    func signIn(email: String, password: String) async throws
    func signUp(name: String, email: String, password: String) async throws
    func signOut() async throws
    /// A valid access token, refreshed if needed; nil when signed out.
    func accessToken() async -> String?
}
