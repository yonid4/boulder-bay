import Foundation

/// Where the app can be. The three roots are chosen from the side menu and switched in
/// place by `AppShellView`; `gymDetail` is pushed on the navigation stack from Map,
/// Rankings and Gyms alike — the one shared destination.
enum AppRoute: Hashable, Sendable {
    case map
    case rankings
    case gyms
    case gymDetail(slug: String)

    var isRoot: Bool {
        if case .gymDetail = self { return false }
        return true
    }

    /// Side-menu order and labels.
    static let roots: [AppRoute] = [.map, .rankings, .gyms]

    var title: String {
        switch self {
        case .map: "Map"
        case .rankings: "Rankings"
        case .gyms: "Gyms"
        case .gymDetail: "Gym"
        }
    }
}

#if DEBUG
extension AppRoute {
    /// Parses the `-BBStartRoute` launch argument: `map`, `rankings`, `gyms`,
    /// `detail:<slug>`. Debug-only, for screenshots and previews of a specific screen —
    /// the mockup's own "startScreen" demo knob.
    static var debugStartRoute: AppRoute? {
        guard let raw = UserDefaults.standard.string(forKey: "BBStartRoute")?.lowercased() else { return nil }
        switch raw {
        case "map": return .map
        case "rankings": return .rankings
        case "gyms": return .gyms
        default:
            if raw.hasPrefix("detail:") { return .gymDetail(slug: String(raw.dropFirst("detail:".count))) }
            return nil
        }
    }

    /// `-BBStartMenuOpen YES` opens the drawer at launch.
    static var debugStartMenuOpen: Bool {
        UserDefaults.standard.bool(forKey: "BBStartMenuOpen")
    }
}
#endif
