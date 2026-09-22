import Supabase
import SwiftUI

/// Two-way gate for now: auth screen without a session, the map with one.
/// Location onboarding and the app shell slot in here once they exist.
struct RootView: View {
    private let authService: AuthService
    @State private var authModel: AuthenticationViewModel

    init(container: AppContainer) {
        authService = container.authService
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
            MapView()
                .overlay(alignment: .bottomTrailing) {
                    // TEMP: sign-out lives in the side menu once the app shell exists.
                    Button("Sign out") {
                        Task { try? await authService.signOut() }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(16)
                }
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
