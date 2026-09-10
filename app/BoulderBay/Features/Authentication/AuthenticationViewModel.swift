import Foundation
import Observation

/// Screen state for sign-in and sign-up: the fields, client-side validation, the
/// in-flight flag and the error line. Talks only to `AuthService`.
@MainActor
@Observable
final class AuthenticationViewModel {
    enum Mode: Equatable {
        case signIn, signUp
    }

    var mode: Mode
    var name = ""
    var email = ""
    var password = ""
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    private let auth: any AuthService

    init(auth: any AuthService, mode: Mode = .signIn) {
        self.auth = auth
        self.mode = mode
    }

    // MARK: Copy, from the mockup

    var title: String { mode == .signUp ? "Create account" : "Welcome back" }

    var subtitle: String {
        mode == .signUp
            ? "See how busy Bay Area bouldering gyms are, and which one to hit right now."
            : "Sign in to see live crowd levels at your gyms."
    }

    var submitTitle: String { mode == .signUp ? "Create account" : "Sign in" }

    var switchTitle: String {
        mode == .signUp ? "Already have an account? Sign in" : "New here? Create an account"
    }

    /// Set while Supabase waits for the email link after sign-up.
    var awaitingConfirmationEmail: String? {
        if case .awaitingEmailConfirmation(let email) = auth.session.state { return email }
        return nil
    }

    // MARK: Actions

    func toggleMode() {
        mode = mode == .signUp ? .signIn : .signUp
        errorMessage = nil
    }

    /// The client-side check run before a request; nil when the form is submittable.
    var validationMessage: String? {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty || password.isEmpty {
            return "Enter your email and password."
        }
        let parts = email.split(separator: "@")
        if parts.count != 2 || !parts[1].contains(".") {
            return "That doesn't look like an email address."
        }
        if mode == .signUp, password.count < 6 {
            return "Use at least 6 characters for your password."
        }
        return nil
    }

    func submit() async {
        guard !isBusy else { return }
        if let validationMessage {
            errorMessage = validationMessage
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch mode {
            case .signIn:
                try await auth.signIn(email: email, password: password)
            case .signUp:
                try await auth.signUp(name: name, email: email, password: password)
            }
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Back from the "check your email" state to a clean sign-in form.
    func returnToSignIn() async {
        try? await auth.signOut()
        mode = .signIn
        password = ""
        errorMessage = nil
    }
}
