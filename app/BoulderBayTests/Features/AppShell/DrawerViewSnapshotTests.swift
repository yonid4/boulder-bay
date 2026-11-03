import SnapshotTesting
import SwiftUI
import Testing

@testable import BoulderBay

/// Reference images live in `__Snapshots__/`. To re-record after an intended visual change,
/// delete the affected PNGs and run the tests once; they fail while recording, then pass.
@MainActor
@Suite
struct DrawerViewSnapshotTests {
    private static let account = DrawerAccount(
        name: "Alex Chen", initials: "AC", detail: "alex.chen@example.com"
    )

    @Test func mapActive() {
        assertDrawer(DrawerView(
            activeRoute: .map,
            account: Self.account,
            isAccountExpanded: .constant(false),
            onSelect: { _ in },
            onSignOut: {}
        ))
    }

    @Test func accountExpandedShowsSignOut() {
        assertDrawer(DrawerView(
            activeRoute: .gyms,
            account: Self.account,
            isAccountExpanded: .constant(true),
            onSelect: { _ in },
            onSignOut: {}
        ))
    }

    @Test func beforeTheProfileLoads() {
        assertDrawer(DrawerView(
            activeRoute: .rankings,
            account: DrawerAccount(profile: nil, state: .loading, email: "alex.chen@example.com"),
            isAccountExpanded: .constant(false),
            onSelect: { _ in },
            onSignOut: {}
        ))
    }

    /// A6 passes `onShowPlaces`; until then the row is hidden.
    @Test func withYourPlacesRow() {
        assertDrawer(DrawerView(
            activeRoute: .map,
            account: Self.account,
            isAccountExpanded: .constant(false),
            onSelect: { _ in },
            onShowPlaces: {},
            onSignOut: {}
        ))
    }

    private func assertDrawer(
        _ drawer: DrawerView,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        // The shell gives the panel 75% of a 393pt phone, over the dimmed screen.
        let view = drawer
            .frame(width: 295, height: 680)
            .frame(width: 393, alignment: .leading)
            .background(Theme.textPrimary.opacity(0.35))
            .background(Theme.background)
        assertSnapshot(
            of: view,
            // Small rendering differences between simulator OS versions shouldn't fail CI.
            as: .image(perceptualPrecision: 0.98, layout: .sizeThatFits),
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}
