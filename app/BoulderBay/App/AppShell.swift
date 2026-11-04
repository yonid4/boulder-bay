import SwiftUI

/// The root screens the side menu switches between. Not pushed: the shell's stack root shows
/// whichever one is current, and pushed screens (gym detail) go on the stack's path.
enum AppRoute: Hashable, CaseIterable {
    case map
    case rankings
    case gyms

    var title: String {
        switch self {
        case .map: "Map"
        case .rankings: "Rankings"
        case .gyms: "Gyms"
        }
    }

    var symbolName: String {
        switch self {
        case .map: "map"
        case .rankings: "text.alignleft"
        case .gyms: "record.circle"
        }
    }
}

/// The signed-in app: a `NavigationStack` whose root is the current `AppRoute`, and the side
/// menu sliding over it from the leading edge. There are no bottom tabs and no Settings
/// screen (root `CLAUDE.md`).
struct AppShell: View {
    private let apiClient: APIClient
    private let appModel: AppModel
    private let authService: AuthService

    @State private var route: AppRoute = .map
    @State private var path = NavigationPath()
    @State private var isDrawerOpen = false
    @State private var isAccountExpanded = false
    /// How far the drawer has been dragged towards closing, ≤ 0.
    @State private var dragOffset: CGFloat = 0
    @State private var isPlacesPresented = false

    /// The mockup's `cubic-bezier(.2, .8, .2, 1)` over 0.3 s.
    private static let drawerAnimation = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)

    init(apiClient: APIClient, appModel: AppModel, authService: AuthService) {
        self.apiClient = apiClient
        self.appModel = appModel
        self.authService = authService
    }

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack(path: $path) {
                rootScreen
                    // Each root screen draws its own header with the menu button.
                    .toolbar(.hidden, for: .navigationBar)
            }
            .environment(\.openDrawer, openDrawerAction)
            .environment(\.showPlaces, showPlacesAction)
            // Hidden from VoiceOver while the menu covers it.
            .accessibilityHidden(isDrawerOpen)

            if isDrawerOpen {
                drawer
            }
        }
        .animation(Self.drawerAnimation, value: isDrawerOpen)
        .sheet(isPresented: $isPlacesPresented) {
            PlacesView(apiClient: apiClient, appModel: appModel)
        }
    }

    @ViewBuilder
    private var rootScreen: some View {
        switch route {
        case .map:
            MapView(apiClient: apiClient, appModel: appModel)
        case .rankings:
            RankingsView()
        case .gyms:
            // A11 wires opening the gym's detail.
            GymsView(appModel: appModel, onOpenGym: { _ in })
        }
    }

    private var drawer: some View {
        ZStack(alignment: .leading) {
            Theme.textPrimary.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { closeDrawer() }
                .accessibilityHidden(true)
                .transition(.opacity)

            DrawerView(
                activeRoute: route,
                account: DrawerAccount(
                    profile: appModel.profile,
                    state: appModel.state,
                    email: authService.session?.user.email
                ),
                isAccountExpanded: $isAccountExpanded,
                onSelect: select,
                onShowPlaces: {
                    closeDrawer()
                    isPlacesPresented = true
                },
                onSignOut: signOut
            )
            .containerRelativeFrame(.horizontal) { width, _ in width * 0.75 }
            .offset(x: dragOffset)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { closeDrawer() }
            .transition(.move(edge: .leading))
        }
        // Swiping towards the leading edge, on the panel or the backdrop, closes it.
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = min(0, value.translation.width)
                }
                .onEnded { value in
                    if value.predictedEndTranslation.width < -120 || value.translation.width < -80 {
                        closeDrawer()
                    } else {
                        withAnimation(Self.drawerAnimation) { dragOffset = 0 }
                    }
                }
        )
    }

    private var openDrawerAction: @MainActor @Sendable () -> Void {
        let isOpen = $isDrawerOpen
        let isExpanded = $isAccountExpanded
        let offset = $dragOffset
        return {
            offset.wrappedValue = 0
            isExpanded.wrappedValue = false
            isOpen.wrappedValue = true
        }
    }

    private var showPlacesAction: @MainActor @Sendable () -> Void {
        let isPresented = $isPlacesPresented
        return { isPresented.wrappedValue = true }
    }

    private func closeDrawer() {
        isDrawerOpen = false
        isAccountExpanded = false
        // `dragOffset` is left as it is so the panel slides out from where the finger let
        // go; opening resets it.
    }

    private func select(_ newRoute: AppRoute) {
        route = newRoute
        path = NavigationPath()
        closeDrawer()
    }

    private func signOut() {
        // The session going nil takes `RootView` back to the auth screen. Nothing on
        // `AppModel` needs clearing: the next sign-in's `bootstrap()` starts afresh.
        Task { try? await authService.signOut() }
    }
}
