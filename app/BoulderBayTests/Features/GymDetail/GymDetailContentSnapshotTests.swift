import SnapshotTesting
import SwiftUI
import Testing

@testable import BoulderBay

/// Reference images live in `__Snapshots__/`. To re-record after an intended visual change,
/// delete the affected PNGs and run the tests once; they fail while recording, then pass.
@MainActor
@Suite
struct GymDetailContentSnapshotTests {
    @Test func fullyPopulated() {
        assertContent(GymDetailContent(detail: GymDetailFixtures.full, isMember: true, isNow: true))
    }

    @Test func weekExpandedWithTodayInBold() {
        assertContent(
            GymDetailContent(
                detail: GymDetailFixtures.full,
                isMember: false,
                isNow: false,
                isWeekExpanded: true
            )
        )
    }

    @Test func sparseGymWithNulls() {
        assertContent(
            GymDetailContent(detail: GymDetailFixtures.sparse, isMember: false, isNow: true)
        )
    }

    private func assertContent(
        _ content: GymDetailContent,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        // The screen insets the content 16pt from the edges of a phone-width screen.
        let view = content.padding(16).frame(width: 393).background(Theme.background)
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
