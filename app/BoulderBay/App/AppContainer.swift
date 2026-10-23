import Foundation
import Supabase

@MainActor
final class AppContainer {
    let authService: AuthService
    let apiClient: APIClient
    let appModel: AppModel

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
        let apiClient = APIClient(baseURL: apiBaseURL, session: apiSession) {
            try await authService.accessToken()
        }
        self.apiClient = apiClient
        let pollListener = PollListener(client: supabaseClient)
        appModel = AppModel(apiClient: apiClient, pollPings: { pollListener.pings() })
    }
}
