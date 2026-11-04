import Foundation
import Testing

@testable import BoulderBay

struct GymListTests {
    private static let gyms = [
        gym(slug: "dogpatch", name: "Dogpatch Boulders", brand: .touchstone, city: "San Francisco"),
        gym(slug: "berkeley", name: "Berkeley Boulders", brand: .movement, city: "Berkeley"),
        gym(slug: "mosaic", name: "Mosaic Boulders", brand: .independent, city: "Oakland"),
        gym(slug: "sunnyvale", name: "Sunnyvale", brand: .movement, city: "Sunnyvale"),
    ]

    private func results(_ query: String) -> [String] {
        GymList.results(in: Self.gyms, query: query).map(\.slug)
    }

    // MARK: Search

    @Test func searchMatchesTheName() {
        #expect(results("Mosaic") == ["mosaic"])
    }

    @Test func searchMatchesTheCity() {
        #expect(results("Oakland") == ["mosaic"])
        #expect(results("San Fran") == ["dogpatch"])
    }

    @Test func searchMatchesTheBrand() {
        #expect(results("Movement") == ["berkeley", "sunnyvale"])
        #expect(results("Touchstone") == ["dogpatch"])
    }

    @Test func searchIgnoresCaseAndSurroundingSpaces() {
        #expect(results("  mOSaIc ") == ["mosaic"])
    }

    @Test func searchKeepsListOrder() {
        #expect(results("boulders") == ["dogpatch", "berkeley", "mosaic"])
    }

    @Test func aBlankQueryIsNoSearch() {
        #expect(results("").isEmpty)
        #expect(results("   ").isEmpty)
    }

    @Test func aQueryMatchingNothingFindsNothing() {
        #expect(results("Tahoe").isEmpty)
    }

    // MARK: Your gyms

    @Test func yourGymsFollowTheMembershipSetNotTheLoadedFlag() {
        let flagged = Self.gym(slug: "flagged", isMember: true)
        let joined = Self.gym(slug: "joined", isMember: false)

        let members = GymList.members(of: [flagged, joined], memberships: ["joined"])

        #expect(members.map(\.slug) == ["joined"])
    }

    @Test func yourGymsKeepListOrder() {
        let members = GymList.members(of: Self.gyms, memberships: ["sunnyvale", "dogpatch"])

        #expect(members.map(\.slug) == ["dogpatch", "sunnyvale"])
    }

    @Test func aMembershipOutsideTheListIsLeftOut() {
        #expect(GymList.members(of: Self.gyms, memberships: ["gone"]).isEmpty)
    }

    @Test func theCountSaysNoneYetThenCountsGyms() {
        #expect(GymList.memberCountLabel(0) == "None yet")
        #expect(GymList.memberCountLabel(1) == "1 gym")
        #expect(GymList.memberCountLabel(2) == "2 gyms")
    }

    // MARK: Helpers

    private static func gym(
        slug: String,
        name: String = "A Gym",
        brand: GymBrand = .independent,
        city: String = "Somewhere",
        isMember: Bool = false
    ) -> Gym {
        Gym(
            slug: slug,
            name: name,
            brand: brand,
            city: city,
            latitude: 37.7,
            longitude: -122.4,
            logoUrl: nil,
            isMember: isMember,
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
