import Foundation
import Testing
import UIKit

@testable import BoulderBay

struct LogoImageTests {
    /// Same rule as the mockup's `initials()`: the first letter of the first two words that
    /// start with a letter, skipping "the", "of" and "and".
    @Test(arguments: [
        ("Dogpatch Boulders", "DB"),
        ("Touchstone Mission Cliffs", "TM"),
        ("The Peak of Fremont", "PF"),
        ("Movement Berkeley", "MB"),
        ("Benchmark Climbing and Fitness", "BC"),
        ("Mosaic", "M"),
        ("studio climbing", "SC"),
        ("8th Street Boulders", "SB"),
        ("", ""),
    ])
    func initials(name: String, expected: String) {
        #expect(LogoImage.initials(for: name) == expected)
    }

    /// Against the real seed files: only logos with colors of their own skip the card's tint.
    @Test(arguments: [
        ("mosaic", true),
        ("movement", true),
        ("benchmark", false),
        ("dogpatch", false),
        ("gwpc", false),
        ("hyperion", false),
        ("ironworks", false),
        ("mission", false),
        ("pipe", false),
        ("studio", false),
        ("the-oaks", false),
        ("the-peak", false),
    ])
    func realLogo(name: String, hasOwnColors: Bool) throws {
        let image = try #require(LogoFixtures.seedLogo(name))
        #expect(image.hasOwnColors == hasOwnColors)
    }

    @Test func anEmptyImageHasNoColors() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        #expect(!image.hasOwnColors)
    }
}

/// The twelve PNGs the logo migration seeds from.
enum LogoFixtures {
    static func seedLogo(_ name: String, testFile: String = #filePath) -> UIImage? {
        // BoulderBayTests/DesignSystem/<file> -> the repo root.
        let root = URL(fileURLWithPath: testFile)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = root.appending(path: "backend/alembic/versions/data/logos/\(name).png")
        return UIImage(contentsOfFile: file.path)
    }
}
