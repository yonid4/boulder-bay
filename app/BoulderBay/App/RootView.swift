import SwiftUI

/// The three-way gate: no session → sign in / sign up; a session but no saved location
/// → onboarding; both → the app shell. Reads `AppContainer.phase`, which already waits
/// for the stores a decision needs.
struct RootView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        Group {
            switch container.phase {
            case .resolving:
                LoadingView(text: "")
            case .preparing:
                LoadingView(text: "Loading your gyms…")
            case .signedOut, .awaitingEmailConfirmation:
                AuthFlowView()
            case .ready:
                if container.locations.current == nil {
                    LocationOnboardingView()
                } else {
                    AppShellView()
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .animation(.easeOut(duration: 0.2), value: container.phase)
        .tint(Theme.brandPrimary)
    }
}

#Preview("Signed in") {
    RootView().environment(AppContainer.preview())
}

#Preview("New account") {
    RootView().environment(AppContainer.preview(fresh: true))
}

#Preview("Signed out") {
    RootView().environment(AppContainer(auth: MockAuthService(), api: PreviewData.api()))
}
