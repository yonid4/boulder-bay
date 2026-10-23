import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import BoulderBay

/// Reference images live in `__Snapshots__/`. To re-record after an intended visual change,
/// delete the affected PNGs and run the tests once; they fail while recording, then pass.
@MainActor
@Suite
struct LogoImageSnapshotTests {
    @Test func initialsWhileLoadingOrWithoutALogo() {
        assertChip(LogoChip(name: "Dogpatch Boulders", image: nil, size: 48, tint: nil))
    }

    @Test func logo() {
        assertChip(LogoChip(name: "Dogpatch Boulders", image: Self.mark, size: 48, tint: nil))
    }

    @Test func tintedInitialsOnTheBestPickCard() {
        assertChip(
            LogoChip(name: "Dogpatch Boulders", image: nil, size: 52, tint: Theme.onBrandPrimaryIcon),
            background: Theme.brandPrimary
        )
    }

    @Test func tintedLogoOnTheBestPickCard() {
        assertChip(
            LogoChip(
                name: "Dogpatch Boulders", image: Self.mark, size: 52, tint: Theme.onBrandPrimaryIcon
            ),
            background: Theme.brandPrimary
        )
    }

    @Test func largeDetailHeaderSize() {
        assertChip(LogoChip(name: "The Peak of Fremont", image: nil, size: 72, tint: nil))
    }

    private func assertChip(
        _ chip: LogoChip,
        background: Color = Theme.card,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        assertSnapshot(
            of: chip.padding(12).background(background),
            // Small rendering differences between simulator OS versions shouldn't fail CI.
            as: .image(perceptualPrecision: 0.98, layout: .sizeThatFits),
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }

    /// A stand-in mark shaped like the real ones: black on transparent, square canvas.
    private static let mark: UIImage = UIGraphicsImageRenderer(
        size: CGSize(width: 64, height: 64)
    ).image { _ in
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 8, y: 48))
        path.addLine(to: CGPoint(x: 32, y: 14))
        path.addLine(to: CGPoint(x: 56, y: 48))
        path.close()
        UIColor.black.setFill()
        path.fill()
    }
}
