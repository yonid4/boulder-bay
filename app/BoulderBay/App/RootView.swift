import Supabase
import SwiftUI

/// Two-way gate for now: auth screen without a session, the app shell with one.
/// The first-place step slots in here once it exists.
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
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        } else if authService.session == nil {
            AuthenticationView(model: authModel)
        } else {
            // One container for the whole signed-in session, so its tasks run once per
            // sign-in and end with it: a sign-out cancels the poll listener, and the next
            // sign-in bootstraps the new account afresh. A first-place gate goes inside.
            ZStack {
                AppShell(apiClient: apiClient, appModel: appModel, authService: authService)
            }
            .task { await appModel.bootstrap() }
            .task { await appModel.listenForPolls() }
        }
    }
}

#Preview {
    let supabase = SupabaseClient(
        supabaseURL: URL(string: "https://preview.supabase.co")!,
        supabaseKey: "preview-key"
    )
    RootView(container: AppContainer(supabaseClient: supabase))
}
