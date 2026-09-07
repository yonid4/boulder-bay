import Foundation

/// Build-time configuration, read from Info.plist so the API host can be
/// swapped per scheme (localhost for the Simulator, a LAN IP for a device).
enum AppConfig {
    static let apiBaseURL: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "BBAPIBaseURL") as? String
        guard let raw, let url = URL(string: raw) else {
            preconditionFailure("BBAPIBaseURL missing or malformed in Info.plist")
        }
        return url
    }()
}
