import Foundation

/// Auth failures as the screens present them. Both services map their own errors here so
/// `AuthenticationViewModel` never sees a supabase-swift type.
enum AuthServiceError: Error, Equatable, Sendable {
    case invalidCredentials
    case emailAlreadyRegistered
    case weakPassword(String)
    case emailNotConfirmed
    case rateLimited
    case network
    case other(String)
}

extension AuthServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "That email and password don't match."
        case .emailAlreadyRegistered: "There's already an account with that email."
        case .weakPassword(let reason): reason.isEmpty ? "Choose a stronger password." : reason
        case .emailNotConfirmed: "Confirm your email first — check your inbox for the link."
        case .rateLimited: "Too many attempts. Wait a moment and try again."
        case .network: "Couldn't reach the sign-in service. Check your connection."
        case .other(let message): message
        }
    }
}
