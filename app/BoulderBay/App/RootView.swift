import Supabase
import SwiftUI

/// What the signed-in half of `RootView` shows, from where `AppModel.bootstrap()` is.
enum SignedInScreen: Equatable {
    /// The account is still loading, so an empty places list means nothing yet.
    case loading
    case failed(String)
    /// Loaded, with no places: the first-place step.
    case firstPlace
    case shell

    init(state: AppModel.LoadState, hasLocations: Bool) {
        switch state {
        case .idle, .loading:
            self = .loading
        case .failed(let message):
            self = .failed(message)
        case .loaded:
            self = hasLocations ? .shell : .firstPlace
        }
    }
}

/// The four-way gate (design §9): a spinner while the session restores, the auth screen
/// without one, then the first-place step until the account has a place, then the shell.
struct RootView: View {
    private let authService: AuthService
    private let apiClient: APIClient
    private let appModel: AppModel
    @State private var authModel: AuthenticationViewModel

    init(container: AppContainer) {
        authService = container.authService
        apiClient = container.apiClient
        appModel = container.appModel
        _authModel = State(initialValue: AuthenticationViewModel(authService: container.authService))
    }

    var body: some View {
        if authService.isRestoringSession {
            spinner
        } else if authService.session == nil {
            AuthenticationView(model: authModel)
        } else {
            // One container for the whole signed-in session, so its tasks run once per
            // sign-in and end with it: a sign-out cancels the poll listener, and the next
            // sign-in bootstraps the new account afresh. The screens inside swap without
            // restarting them.
            ZStack {
                switch SignedInScreen(
                    state: appModel.state, hasLocations: !appModel.locations.isEmpty
                ) {
                case .loading:
                    spinner
                case .failed(let message):
                    AccountLoadFailedView(
                        message: message,
                        onRetry: { Task { await appModel.bootstrap() } },
                        onSignOut: signOut
                    )
                case .firstPlace:
                    FirstPlaceView(apiClient: apiClient, appModel: appModel, onSignOut: signOut)
                case .shell:
                    AppShell(apiClient: apiClient, appModel: appModel, authService: authService)
                }
            }
            .task { await appModel.bootstrap() }
            .task { await appModel.listenForPolls() }
        }
    }

    private var spinner: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }

    private func signOut() {
        // The session going nil brings back the auth screen; the next sign-in's
        // `bootstrap()` starts afresh.
        Task { try? await authService.signOut() }
    }
}

#Preview {
    let supabase = SupabaseClient(
        supabaseURL: URL(string: "https://preview.supabase.co")!,
        supabaseKey: "preview-key"
    )
    RootView(container: AppContainer(supabaseClient: supabase))
}
