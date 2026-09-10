import SwiftUI

/// The signed-in app: one `NavigationStack` whose root is the drawer's selection, with
/// the gym detail pushed on top, and the side menu overlaid across everything.
struct AppShellView: View {
    @Environment(AppContainer.self) private var container
    @State private var shell = AppShellViewModel()

    var body: some View {
        @Bindable var shell = shell
        NavigationStack(path: $shell.path) {
            rootScreen
                .navigationDestination(for: AppRoute.self) { route in
                    if case .gymDetail(let slug) = route {
                        GymDetailView(slug: slug)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .overlay { SideMenuOverlay() }
        .environment(shell)
    }

    @ViewBuilder
    private var rootScreen: some View {
        switch shell.root {
        case .map: MapView()
        case .rankings: RankingsView()
        case .gyms: GymsView()
        case .gymDetail: EmptyView()
        }
    }
}

#Preview {
    AppShellView().environment(AppContainer.preview())
}
