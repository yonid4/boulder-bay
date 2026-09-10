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
