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

// MARK: - Placeholders, replaced screen by screen

struct GymsView: View {
    var body: some View { PlaceholderScreen(route: .gyms) }
}

struct GymDetailView: View {
    @Environment(AppShellViewModel.self) private var shell
    let slug: String

    var body: some View {
        VStack {
            HStack { BackButton { shell.pop() }; Spacer() }
            Spacer()
            Text(slug).font(Typography.title).foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(Spacing.screen)
        .background(Theme.background.ignoresSafeArea())
    }
}

private struct PlaceholderScreen: View {
    @Environment(AppShellViewModel.self) private var shell
    let route: AppRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScreenHeader(title: route.title) { shell.openMenu() }
            Button("Open Movement Belmont") { shell.openDetail(slug: "mv-belmont") }
                .buttonStyle(PillButtonStyle(kind: .add))
            Spacer()
        }
        .padding(.horizontal, Spacing.header)
        .padding(.top, Spacing.topChrome)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
    }
}

#Preview {
    AppShellView().environment(AppContainer.preview())
}
