import Foundation
import Supabase

@MainActor
@Observable
final class AuthenticationViewModel {
    enum Mode {
        case signIn
        case signUp
    }

    var mode: Mode = .signIn
    var email = ""
    var password = ""
    var displayName = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?
    private(set) var isAwaitingEmailConfirmation = false

    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    var title: String {
        switch mode {
        case .signIn: "Welcome back"
        case .signUp: "Create account"
        }
    }

    var subtitle: String {
        switch mode {
        case .signIn: "Sign in to see live crowd levels at your gyms."
        case .signUp: "See how busy Bay Area bouldering gyms are, and which one to hit right now."
        }
    }

    var submitLabel: String {
        switch mode {
        case .signIn: "Sign in"
        case .signUp: "Create account"
        }
    }

    var switchModeLabel: String {
        switch mode {
        case .signIn: "New here? Create an account"
        case .signUp: "Already have an account? Sign in"
        }
    }

    var canSubmit: Bool {
        guard !isSubmitting, !email.isEmpty, !password.isEmpty else { return false }
        return mode == .signIn || !displayName.isEmpty
    }

    func toggleMode() {
        mode = mode == .signIn ? .signUp : .signIn
        errorMessage = nil
        isAwaitingEmailConfirmation = false
    }

    func submit() async {
        isSubmitting = true
        errorMessage = nil
        isAwaitingEmailConfirmation = false
        defer { isSubmitting = false }

        do {
            switch mode {
            case .signIn:
                try await authService.signIn(email: email, password: password)
                resetForm()
            case .signUp:
                let result = try await authService.signUp(
                    email: email, password: password, displayName: displayName
                )
                switch result {
                case .signedIn:
                    resetForm()
                case .confirmationRequired:
                    password = ""
                    isAwaitingEmailConfirmation = true
                }
            }
        } catch AuthServiceError.invalidDisplayName {
            errorMessage = "Name must be 1–80 letters and spaces."
        } catch let error as AuthError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // The same instance is shown again after sign-out; don't carry credentials over.
    private func resetForm() {
        mode = .signIn
        email = ""
        password = ""
        displayName = ""
    }
}
