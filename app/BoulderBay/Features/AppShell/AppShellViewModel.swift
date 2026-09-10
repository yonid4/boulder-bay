import Foundation
import Observation

/// Navigation state for the signed-in app: which drawer root is showing, what's pushed
/// on top of it, and whether the drawer is open. Shared with every screen through the
/// environment so any of them can open the menu or push the gym detail.
@MainActor
@Observable
final class AppShellViewModel {
    /// The drawer root on screen.
    private(set) var root: AppRoute = .map
    /// Pushed destinations — only `.gymDetail` in v1.
    var path: [AppRoute] = []
    var isMenuOpen = false
    /// The sign-out popover above the user card.
    var isUserMenuOpen = false

    /// Picks a root from the drawer: pops anything pushed and closes the menu.
    func select(_ route: AppRoute) {
        guard route.isRoot else { return }
        root = route
        path.removeAll()
        closeMenu()
    }

    func openDetail(slug: String) {
        path.append(.gymDetail(slug: slug))
    }

    func pop() {
        _ = path.popLast()
    }

    func openMenu() {
        isUserMenuOpen = false
        isMenuOpen = true
    }

    func closeMenu() {
        isMenuOpen = false
        isUserMenuOpen = false
    }

    func toggleUserMenu() {
        isUserMenuOpen.toggle()
    }
}
