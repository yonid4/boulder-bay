import SnapshotTesting
import SwiftUI
import Testing

@testable import BoulderBay

/// Reference images live in `__Snapshots__/`. To re-record after an intended visual change,
/// delete the affected PNGs and run the tests once; they fail while recording, then pass.
@MainActor
@Suite
struct BestPickButtonSnapshotTests {
    @Test func rightNow() {
        assertButton(BestPickButton(title: "Best right now", isLoading: false, action: {}))
    }

    @Test func atAnotherHour() {
        assertButton(BestPickButton(title: "Best at 7 PM", isLoading: false, action: {}))
    }

    @Test func whileLoading() {
        assertButton(BestPickButton(title: "Best right now", isLoading: true, action: {}))
    }

    private func assertButton(
        _ button: BestPickButton,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        assertSnapshot(
            // With a bare `.sizeThatFits`, the one-line label collapses.
            of: button.frame(width: 393, height: 82).background(Theme.background),
            as: .image(perceptualPrecision: 0.98, layout: .sizeThatFits),
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}
