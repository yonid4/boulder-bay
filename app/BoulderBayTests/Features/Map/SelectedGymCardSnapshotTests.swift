import SnapshotTesting
import SwiftUI
import Testing

@testable import BoulderBay

/// Reference images live in `__Snapshots__/`. To re-record after an intended visual change,
/// delete the affected PNGs and run the tests once; they fail while recording, then pass.
@MainActor
@Suite
struct SelectedGymCardSnapshotTests {
    @Test func openGym() {
        assertCard(SelectedGymCard(gym: Self.gym(isOpen: true), onDismiss: {}))
    }

    @Test func closedGym() {
        assertCard(SelectedGymCard(gym: Self.gym(isOpen: false), onDismiss: {}))
    }

    @Test func longNameTruncatesToOneLine() {
        let gym = Self.gym(name: "Touchstone Mission Cliffs Bouldering and Fitness", isOpen: true)
        assertCard(SelectedGymCard(gym: gym, onDismiss: {}))
    }

    private func assertCard(
        _ card: SelectedGymCard,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        // The map screen insets the card 16pt from the edges of a phone-width screen.
        let view = card.padding(16).frame(width: 393).background(Theme.background)
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

    private static func gym(name: String = "Dogpatch Boulders", isOpen: Bool) -> Gym {
        Gym(
            slug: "dogpatch",
            name: name,
            brand: .touchstone,
            city: "San Francisco",
            latitude: 37.7567,
            longitude: -122.3903,
            logoUrl: nil,
            isMember: false,
            busyness: ResolvedBusyness(
                at: Date(timeIntervalSince1970: 1_789_322_400),
                isOpen: isOpen,
                busyPct: nil,
                level: nil,
                source: nil
            )
        )
    }
}
