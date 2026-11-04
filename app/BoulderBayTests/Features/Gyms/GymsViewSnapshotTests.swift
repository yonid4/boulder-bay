import SnapshotTesting
import SwiftUI
import Testing

@testable import BoulderBay

/// Reference images live in `__Snapshots__/`. To re-record after an intended visual change,
/// delete the affected PNGs and run the tests once; they fail while recording, then pass.
@MainActor
@Suite
struct GymsViewSnapshotTests {
    private static let gyms = [
        gym(slug: "dogpatch", name: "Dogpatch Boulders", brand: .touchstone, city: "San Francisco"),
        gym(slug: "berkeley", name: "Berkeley Boulders", brand: .touchstone, city: "Berkeley"),
        gym(slug: "movement-sv", name: "Movement Sunnyvale", brand: .movement, city: "Sunnyvale"),
        gym(slug: "mosaic", name: "Mosaic Boulders", brand: .independent, city: "Oakland"),
    ]

    // MARK: Rows

    @Test func rowAdd() {
        assertRow(GymRow(gym: Self.gyms[0], action: .add, onOpen: {}, onToggle: {}))
    }

    @Test func rowAdded() {
        assertRow(GymRow(gym: Self.gyms[0], action: .added, onOpen: {}, onToggle: {}))
    }

    @Test func rowRemove() {
        assertRow(GymRow(gym: Self.gyms[0], action: .remove, onOpen: {}, onToggle: {}))
    }

    @Test func rowPending() {
        assertRow(GymRow(gym: Self.gyms[0], action: .added, isPending: true, onOpen: {}, onToggle: {}))
    }

    @Test func rowLongNameTruncates() {
        let gym = Self.gym(
            slug: "long",
            name: "Touchstone Mission Cliffs Bouldering and Fitness",
            brand: .touchstone,
            city: "San Francisco"
        )
        assertRow(GymRow(gym: gym, action: .add, onOpen: {}, onToggle: {}))
    }

    // MARK: Screen

    @Test func noneYet() {
        assertScreen(content(memberships: []))
    }

    @Test func someGyms() {
        assertScreen(content(memberships: ["dogpatch", "mosaic"]))
    }

    @Test func searchResults() {
        assertScreen(content(memberships: ["dogpatch"], query: "touchstone"))
    }

    @Test func searchWithNoMatch() {
        assertScreen(content(memberships: [], query: "Tahoe"))
    }

    @Test func aToggleInFlight() {
        assertScreen(content(memberships: ["dogpatch"], pending: ["berkeley"], query: "touchstone"))
    }

    @Test func membershipErrorBanner() {
        assertScreen(content(
            memberships: ["dogpatch"],
            membershipError: "The server returned an error (500)."
        ))
    }

    @Test func listLoading() {
        assertScreen(content(gyms: [], memberships: ["dogpatch"], loadState: .loading))
    }

    @Test func listFailed() {
        assertScreen(content(
            gyms: [],
            memberships: ["dogpatch"],
            loadState: .failed("The server returned an error (500).")
        ))
    }

    /// A reload for another hour failed, but the list it left behind is all this screen needs.
    @Test func failedReloadKeepsTheList() {
        assertScreen(content(
            memberships: ["dogpatch"],
            loadState: .failed("The server returned an error (500).")
        ))
    }

    // MARK: Helpers

    private func content(
        gyms: [Gym] = Self.gyms,
        memberships: Set<String>,
        pending: Set<String> = [],
        loadState: AppModel.LoadState = .loaded,
        query: String = "",
        membershipError: String? = nil
    ) -> GymsContent {
        GymsContent(
            gyms: gyms,
            memberships: memberships,
            pendingMemberships: pending,
            loadState: loadState,
            query: .constant(query),
            membershipError: membershipError
        )
    }

    private func assertRow(
        _ row: GymRow,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        // Rows sit in a white card inset 16pt from the edges of a phone-width screen.
        let view = row
            .background(Theme.card)
            .padding(16)
            .frame(width: 393)
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

    private func assertScreen(
        _ content: GymsContent,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        assertSnapshot(
            of: content.frame(width: 393, height: 720),
            // Small rendering differences between simulator OS versions shouldn't fail CI.
            as: .image(perceptualPrecision: 0.98, layout: .sizeThatFits),
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }

    private static func gym(slug: String, name: String, brand: GymBrand, city: String) -> Gym {
        Gym(
            slug: slug,
            name: name,
            brand: brand,
            city: city,
            latitude: 37.7567,
            longitude: -122.3903,
            logoUrl: nil,
            isMember: false,
            busyness: ResolvedBusyness(
                at: Date(timeIntervalSince1970: 1_789_322_400),
                isOpen: true,
                busyPct: nil,
                level: nil,
                source: nil
            )
        )
    }
}
