import Testing

@testable import BoulderBay

struct InitialsTests {
    @Test(arguments: [
        ("Great Western Power Company", "GW"),
        ("The Oaks Climbing", "OC"),
        ("The Peak of Fremont", "PF"),
        ("Mosaic Boulders", "MB"),
        ("Movement San Francisco", "MS"),
        ("Benchmark Berkeley", "BB"),
        ("Pacific Pipe", "PP"),
        ("Mosaic", "M"),
        ("3rd Street Gym", "SG"),
        ("", ""),
    ])
    func monogramFollowsTheMockupRule(name: String, expected: String) {
        #expect(name.initials == expected)
    }
}
