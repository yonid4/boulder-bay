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
        assertContent(
            GymDetailContent(
                detail: GymDetailFixtures.full, isMember: true, isNow: true,
                now: GymDetailFixtures.at
            )
        )
    }

    @Test func withABestTime() {
        assertContent(
            GymDetailContent(
                detail: GymDetailFixtures.fullWithBestTime, isMember: true, isNow: true,
                now: GymDetailFixtures.at
            )
        )
    }

    @Test func weekExpandedWithTodayInBold() {
        assertContent(
            GymDetailContent(
                detail: GymDetailFixtures.full,
                isMember: false,
                isNow: false,
                now: GymDetailFixtures.at,
                isWeekExpanded: true
            )
        )
    }

    @Test func sparseGymWithNulls() {
        assertContent(
            GymDetailContent(
                detail: GymDetailFixtures.sparse, isMember: false, isNow: true,
                now: GymDetailFixtures.at
            )
        )
    }

    /// A real day's worth of bars, to check they and their labels fit the card.
    @Test func aFullDayOfBars() {
        let percents = [12, 18, 25, 31, 42, 55, 68, 74, 81, 63, 47, 30, 19, 8]
        let points = percents.enumerated().map { hour, percent in
            GymDetailFixtures.point(
                hoursAfterAt: hour - 4,
                percent: percent,
                level: percent < 40 ? .quiet : percent < 70 ? .moderate : .packed
            )
        }
        let chart = ForecastChart(
            forecast: GymDetailFixtures.forecast(points: points),
            at: GymDetailFixtures.at,
            now: GymDetailFixtures.at
        )
        assertSnapshot(
            of: chart.padding(18).frame(width: 361).background(Theme.card),
            as: .image(perceptualPrecision: 0.98, layout: .sizeThatFits)
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
