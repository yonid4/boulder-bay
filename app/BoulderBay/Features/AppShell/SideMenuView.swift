import SwiftUI

/// The drawer, overlaid on the whole shell: a dimmed backdrop and a 75%-wide panel
/// that slides in from the left. Tap the backdrop or drag left to close.
struct SideMenuOverlay: View {
    @Environment(AppShellViewModel.self) private var shell
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.75
            ZStack(alignment: .leading) {
                if shell.isMenuOpen {
                    Theme.textPrimary.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { shell.closeMenu() }
                        .transition(.opacity)
                }
                SideMenuView()
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background(
                        Theme.surfaceElevated,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 0, bottomLeadingRadius: 0,
                            bottomTrailingRadius: Radius.sheet, topTrailingRadius: Radius.sheet,
                            style: .continuous
                        )
                    )
                    .shadow(color: Theme.shadow.opacity(0.25), radius: 20, x: 12)
                    .offset(x: shell.isMenuOpen ? min(dragOffset, 0) : -width - 40)
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in dragOffset = value.translation.width }
                            .onEnded { value in
                                if value.translation.width < -width / 3 || value.predictedEndTranslation.width < -width {
                                    shell.closeMenu()
                                }
                                dragOffset = 0
                            }
                    )
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: shell.isMenuOpen)
            .animation(.interactiveSpring(), value: dragOffset)
        }
        .allowsHitTesting(shell.isMenuOpen)
    }
}

/// The panel's contents: app name, the three routes, and the user card pinned to the
/// bottom with its sign-out popover.
struct SideMenuView: View {
    @Environment(AppShellViewModel.self) private var shell

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Boulder Bay")
                .font(Typography.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ForEach(AppRoute.roots, id: \.self) { route in
                MenuRow(route: route, isActive: shell.root == route) { shell.select(route) }
            }

            Spacer(minLength: 0)

            ProfileHeaderView()
        }
        .padding(.horizontal, 16)
        .padding(.top, 72)
        .padding(.bottom, 44)
    }
}

private struct MenuRow: View {
    let route: AppRoute
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RouteIcon(route: route)
                    .frame(width: 28, height: 28)
                Text(route.title)
                    .font(Typography.menuRow)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(
                isActive ? Theme.surface : .clear,
                in: RoundedRectangle(cornerRadius: Radius.menuRow, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// The mockup's three line icons, drawn rather than pulled from SF Symbols so they
/// match its weight.
private struct RouteIcon: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .map:
            ZStack {
                RoundedRectangle(cornerRadius: 4).strokeBorder(lineWidth: 1.8).frame(width: 18, height: 16)
                Circle().frame(width: 6, height: 6)
            }
        case .rankings:
            VStack(alignment: .leading, spacing: 2.5) {
                Capsule().frame(width: 18, height: 3)
                Capsule().frame(width: 13, height: 3)
                Capsule().frame(width: 8, height: 3)
            }
        case .gyms:
            ZStack {
                Circle().strokeBorder(lineWidth: 1.8).frame(width: 16, height: 16)
                Circle().frame(width: 6, height: 6)
            }
        case .gymDetail:
            EmptyView()
        }
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        SideMenuView()
            .frame(width: 300)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceElevated)
    }
    .environment(AppShellViewModel())
    .environment(AppContainer.preview())
}
