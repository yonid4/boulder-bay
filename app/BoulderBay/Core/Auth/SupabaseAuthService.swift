import Foundation
import Supabase

/// Supabase Auth through the official `supabase-swift` client. Sessions persist in the
/// keychain via the client's default storage, so a relaunch restores the user; the
/// `authStateChanges` stream keeps `session` in step with refreshes and sign-outs.
///
/// FastAPI verifies the ES256 access token this hands out against the project's JWKS.
@MainActor
final class SupabaseAuthService: AuthService {
    let session = AuthSession()

    private let client: SupabaseClient
    private var listener: Task<Void, Never>?

    init(url: URL, anonKey: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }

    /// Only when `AppConfig` has both values; the composition root falls back to
    /// `MockAuthService` otherwise.
    convenience init?() {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else {
            return nil
        }
        self.init(url: url, anonKey: key)
    }

    func start() async {
        guard listener == nil else { return }
        let auth = client.auth
        listener = Task { [weak self] in
            // The stream opens with `.initialSession`, which resolves `.resolving`.
            for await (event, session) in auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let session {
                        self.session.transition(to: .signedIn(Self.user(from: session)))
                    } else if case .awaitingEmailConfirmation = self.session.state {
                        break  // keep the confirmation prompt on screen
                    } else {
                        self.session.transition(to: .signedOut)
                    }
                case .signedOut, .userDeleted:
                    self.session.transition(to: .signedOut)
                case .passwordRecovery, .mfaChallengeVerified:
                    break
                }
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        do {
            let supabaseSession = try await client.auth.signIn(email: email, password: password)
            session.transition(to: .signedIn(Self.user(from: supabaseSession)))
        } catch {
            throw Self.map(error)
        }
    }

    func signUp(name: String, email: String, password: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                data: trimmed.isEmpty ? nil : ["display_name": .string(trimmed)]
            )
            switch response {
            case .session(let supabaseSession):
                var user = Self.user(from: supabaseSession)
                user.isNewAccount = true
                session.transition(to: .signedIn(user))
            case .user:
                // Email confirmation is on for the project; no session until the link is tapped.
                session.transition(to: .awaitingEmailConfirmation(email: email))
            }
        } catch {
            throw Self.map(error)
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            // A failed remote revoke still clears the local session in supabase-swift;
            // the UI outcome is the same either way.
            if case AuthError.sessionMissing = error {} else { throw Self.map(error) }
        }
        session.transition(to: .signedOut)
    }

    func accessToken() async -> String? {
        try? await client.auth.session.accessToken
    }

    // MARK: Mapping

    private static func user(from session: Session) -> AuthUser {
        let user = session.user
        let name: String? = if case .string(let value)? = user.userMetadata["display_name"] {
            value
        } else {
            nil
        }
        return AuthUser(id: user.id, email: user.email ?? "", displayName: name)
    }

    private static func map(_ error: any Error) -> AuthServiceError {
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .other(urlError.localizedDescription) : .network
        }
        guard let authError = error as? AuthError else {
            return .other(error.localizedDescription)
        }
        switch authError.errorCode {
        case .invalidCredentials: return .invalidCredentials
        case .userAlreadyExists, .emailExists: return .emailAlreadyRegistered
        case .weakPassword: return .weakPassword(authError.message)
        case .emailNotConfirmed: return .emailNotConfirmed
        case .overRequestRateLimit, .overEmailSendRateLimit: return .rateLimited
        default: return .other(authError.message)
        }
    }
}
