import Foundation
import Supabase

@MainActor
final class AppContainer {
    let authService: AuthService
    let apiClient: APIClient
    let appModel: AppModel
    let logoStore: LogoStore

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
        // Its own client, so logo bytes go through a session that writes nothing to disk.
        logoStore = LogoStore(
            client: APIClient(baseURL: apiBaseURL, session: LogoStore.makeSession()) {
                try await authService.accessToken()
            }
        )
    }
}
