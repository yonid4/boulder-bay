import Foundation
import Testing

@testable import BoulderBay

@MainActor
struct AuthenticationViewModelTests {
    private func makeAuth() -> MockAuthService {
        let name = "AuthVMTests-\(UUID().uuidString)"
        return MockAuthService(defaults: UserDefaults(suiteName: name)!, initialState: .signedOut)
    }

    @Test func copyFollowsTheMode() {
        let model = AuthenticationViewModel(auth: makeAuth())
        #expect(model.title == "Welcome back")
        #expect(model.submitTitle == "Sign in")
        #expect(model.switchTitle == "New here? Create an account")

        model.toggleMode()
        #expect(model.mode == .signUp)
        #expect(model.title == "Create account")
        #expect(model.submitTitle == "Create account")
        #expect(model.switchTitle == "Already have an account? Sign in")
    }

    @Test func validatesBeforeCallingTheService() async {
        let auth = makeAuth()
        let model = AuthenticationViewModel(auth: auth)

        await model.submit()
        #expect(model.errorMessage == "Enter your email and password.")

        model.email = "nope"
        model.password = "secret1"
        await model.submit()
        #expect(model.errorMessage == "That doesn't look like an email address.")

        model.mode = .signUp
        model.email = "sam@lee.io"
        model.password = "abc"
        await model.submit()
        #expect(model.errorMessage == "Use at least 6 characters for your password.")
        #expect(auth.session.state == .signedOut)
    }

    @Test func signInSucceedsAndClearsThePassword() async {
        let auth = makeAuth()
        let model = AuthenticationViewModel(auth: auth)
        model.email = " Sam@Lee.io "
        model.password = "climb-on"

        await model.submit()

        #expect(model.errorMessage == nil)
        #expect(model.password.isEmpty)
        #expect(auth.session.user?.email == "sam@lee.io")
        #expect(!model.isBusy)
    }

    @Test func serviceErrorsSurfaceAsText() async {
        let auth = makeAuth()
        let model = AuthenticationViewModel(auth: auth)
        model.email = "sam@lee.io"
        model.password = "short"  // passes sign-in validation, rejected by the mock

        await model.submit()

        #expect(model.errorMessage == AuthServiceError.invalidCredentials.errorDescription)
        #expect(auth.session.state == .signedOut)
    }

    @Test func signUpPassesTheName() async {
        let auth = makeAuth()
        let model = AuthenticationViewModel(auth: auth, mode: .signUp)
        model.name = "Sam Lee"
        model.email = "sam@lee.io"
        model.password = "climb-on"

        await model.submit()

        #expect(auth.session.user?.displayName == "Sam Lee")
        #expect(auth.session.user?.isNewAccount == true)
    }
}
