import Foundation

/// Build-time configuration, read from Info.plist so hosts and keys can be
/// swapped per scheme (localhost for the Simulator, a LAN IP for a device).
enum AppConfig {
    static let apiBaseURL: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "BBAPIBaseURL") as? String
        guard let raw, let url = URL(string: raw) else {
            preconditionFailure("BBAPIBaseURL missing or malformed in Info.plist")
        }
        return url
    }()

    /// Supabase project URL. `nil` until `BB_SUPABASE_URL` is set in `project.yml`.
    static let supabaseURL: URL? = string(for: "BBSupabaseURL").flatMap(URL.init(string:))

    /// Supabase anon key — public by design and RLS-gated, so it ships in the bundle.
    /// `nil` until `BB_SUPABASE_ANON_KEY` is set in `project.yml`.
    static let supabaseAnonKey: String? = string(for: "BBSupabaseAnonKey")

    private static func string(for key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        // An unset build setting expands to an empty string, not a missing key.
        return (value?.isEmpty ?? true) ? nil : value
    }
}
