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

    /// Supabase project URL. `nil` until `BB_SUPABASE_URL` is set in
    /// `app/Config/Supabase.xcconfig`.
    static let supabaseURL: URL? = string(for: "BBSupabaseURL").flatMap(URL.init(string:))

    /// Supabase anon key — public by design and RLS-gated, so it ships in the bundle.
    /// `nil` until `BB_SUPABASE_ANON_KEY` is set in `app/Config/Supabase.xcconfig`.
    static let supabaseAnonKey: String? = string(for: "BBSupabaseAnonKey")

    /// Whether both Supabase values are present. When false the app runs on
    /// `MockAuthService`.
    static var isSupabaseConfigured: Bool { supabaseURL != nil && supabaseAnonKey != nil }

    /// Serve data from the in-app `MockAPIClient` instead of the backend.
    ///
    /// Resolution order: the `-BBUseMockAPI YES|NO` launch argument (Xcode registers
    /// launch arguments into `UserDefaults`, so a scheme can flip this for one run
    /// without touching a committed file), then the `BB_USE_MOCK_API` build setting
    /// surfaced through `Info.plist` — `YES` for Debug, `NO` for Release.
    static let useMockAPI: Bool = {
        if let override = UserDefaults.standard.object(forKey: "BBUseMockAPI") {
            return yes(override)
        }
        return string(for: "BBUseMockAPI").map(yes) ?? false
    }()

    private static func yes(_ value: Any) -> Bool {
        switch value {
        case let bool as Bool: bool
        case let string as String: ["yes", "true", "1"].contains(string.lowercased())
        case let number as NSNumber: number.boolValue
        default: false
        }
    }

    private static func string(for key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        // An unset build setting expands to an empty string, not a missing key.
        return (value?.isEmpty ?? true) ? nil : value
    }
}
