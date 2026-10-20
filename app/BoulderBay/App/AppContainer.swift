import Foundation
import Supabase

@MainActor
final class AppContainer {
    let authService: AuthService
    let apiClient: APIClient

    convenience init() {
        self.init(
            supabaseClient: SupabaseClient(
                supabaseURL: AppConfig.supabaseURL,
                supabaseKey: AppConfig.supabaseAnonKey,
                options: SupabaseClientOptions(
                    auth: .init(emitLocalSessionAsInitialSession: true)
                )
            )
        )
    }

    init(
        supabaseClient: SupabaseClient,
        apiBaseURL: URL = AppConfig.apiBaseURL,
        apiSession: URLSession = .shared
    ) {
        let authService = AuthService(client: supabaseClient)
        self.authService = authService
        apiClient = APIClient(baseURL: apiBaseURL, session: apiSession) {
            try await authService.accessToken()
        }
    }
}
