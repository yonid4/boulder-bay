import SnapshotTesting
import SwiftUI
import Testing

@testable import BoulderBay

/// Reference images live in `__Snapshots__/`. To re-record after an intended visual change,
/// delete the affected PNGs and run the tests once; they fail while recording, then pass.
@MainActor
@Suite
struct GymPinViewSnapshotTests {
    @Test func openWithLabel() {
        assertPin(GymPinView(gym: Self.gym(isOpen: true), isSelected: false, showsLabel: true))
    }

    @Test func closedWithLabel() {
        assertPin(GymPinView(gym: Self.gym(isOpen: false), isSelected: false, showsLabel: true))
    }

    @Test func selectedWithLabel() {
        assertPin(GymPinView(gym: Self.gym(isOpen: true), isSelected: true, showsLabel: true))
    }

    @Test func dotOnlyWhenZoomedOut() {
        assertPin(GymPinView(gym: Self.gym(isOpen: true), isSelected: false, showsLabel: false))
    }

    @Test func longNameWrapsThenTruncates() {
        let gym = Self.gym(name: "Touchstone Mission Cliffs Bouldering", isOpen: true)
        assertPin(GymPinView(gym: gym, isSelected: false, showsLabel: true))
    }

    private func assertPin(
        _ pin: GymPinView,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        // Padding leaves room for the shadows and the selected pin's 1.25× scale.
        let view = pin.padding(24).background(Theme.background)
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
