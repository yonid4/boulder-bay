import Testing

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
}
