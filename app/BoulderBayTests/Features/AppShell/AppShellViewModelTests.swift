import Testing

@testable import BoulderBay

@MainActor
struct AppShellViewModelTests {
    @Test func startsOnTheMapWithTheMenuClosed() {
        let shell = AppShellViewModel()
        #expect(shell.root == .map)
        #expect(shell.path.isEmpty)
        #expect(!shell.isMenuOpen)
    }

    @Test func selectingARootPopsAndClosesTheMenu() {
        let shell = AppShellViewModel()
        shell.openDetail(slug: "mv-belmont")
        shell.openMenu()
        shell.toggleUserMenu()

        shell.select(.rankings)

        #expect(shell.root == .rankings)
        #expect(shell.path.isEmpty)
        #expect(!shell.isMenuOpen)
        #expect(!shell.isUserMenuOpen)
    }

    @Test func detailIsNeverARoot() {
        let shell = AppShellViewModel()
        shell.select(.gymDetail(slug: "mosaic"))
        #expect(shell.root == .map)

        shell.openDetail(slug: "mosaic")
        #expect(shell.path == [.gymDetail(slug: "mosaic")])
        shell.pop()
        #expect(shell.path.isEmpty)
        shell.pop()
        #expect(shell.path.isEmpty)
    }

    @Test func openingTheMenuClosesTheUserPopover() {
        let shell = AppShellViewModel()
        shell.openMenu()
        shell.toggleUserMenu()
        #expect(shell.isUserMenuOpen)
        shell.closeMenu()
        shell.openMenu()
        #expect(!shell.isUserMenuOpen)
    }
}
