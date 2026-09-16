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

    /// Supabase project URL from the developer's ignored Supabase.xcconfig.
    static let supabaseURL: URL = {
        let raw = requiredString(for: "BBSupabaseURL", buildSetting: "BB_SUPABASE_URL")
        guard let url = URL(string: raw), url.scheme == "https", url.host() != nil else {
            preconditionFailure("BB_SUPABASE_URL missing or malformed in Supabase.xcconfig")
        }
        return url
    }()

    /// Supabase anon key — public by design and RLS-gated, so it ships in the bundle.
    static let supabaseAnonKey: String = requiredString(
        for: "BBSupabaseAnonKey",
        buildSetting: "BB_SUPABASE_ANON_KEY"
    )

    private static func requiredString(for key: String, buildSetting: String) -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        // An unset build setting expands to an empty string, not a missing key.
        guard let value, !value.isEmpty else {
            preconditionFailure("\(buildSetting) is required; set it in app/Config/Supabase.xcconfig")
        }
        return value
    }
}
