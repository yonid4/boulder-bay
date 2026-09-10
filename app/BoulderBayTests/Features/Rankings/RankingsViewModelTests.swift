import Foundation
import Testing

@testable import BoulderBay

@MainActor
struct RankingsViewModelTests {
    private func makeModel(fresh: Bool = false) async -> (AppContainer, RankingsViewModel) {
        let profile = MockAPIClient.Account.previewProfile
        let container = AppContainer(
            auth: MockAuthService.signedIn(as: .preview),
            api: MockAPIClient(
                account: fresh ? .fresh(profile: profile) : .seeded(profile: profile, now: wednesday5pm),
                now: { wednesday5pm }
            ),
            now: { wednesday5pm }
        )
        await container.gyms.load()
        await container.locations.load()
        await container.memberships.load()
        let model = RankingsViewModel(
            gyms: container.gyms, rankings: container.rankings,
            memberships: container.memberships, locations: container.locations
        )
        await model.load()
        return (container, model)
    }

    @Test func showsTheBestPickPlusSevenMore() async {
        let (container, model) = await makeModel()

        #expect(model.ranked.count == 16)
        #expect(model.best?.rank == 1)
        #expect(model.best?.id == container.rankings.best?.slug)
        #expect(model.rest.count == 7)
        #expect(model.rest.map(\.rank) == Array(2...8))
        #expect(model.subtitle == "Live, 5 PM")
        #expect(model.bestPickLabel == "Best pick right now")
        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)
    }

    @Test func whyLineCoversMemberAndNonMemberNowAndLater() async {
        let (container, model) = await makeModel()
        let member = RankedGym(
            entry: RankingEntry(slug: "mv-belmont", rank: 1, score: 70, busyPct: 30, isOpen: true, isMember: true, travelMinutes: 12, distanceMiles: 4),
            gym: PreviewData.belmont
        )
        let other = RankedGym(
            entry: RankingEntry(slug: "hyperion", rank: 2, score: 60, busyPct: 55, isOpen: true, isMember: false, travelMinutes: 9, distanceMiles: 2),
            gym: PreviewData.gym("hyperion")
        )
        let closed = RankedGym(
            entry: RankingEntry(slug: "mosaic", rank: 3, score: 0, busyPct: nil, isOpen: false, isMember: false, travelMinutes: 48, distanceMiles: 31),
            gym: PreviewData.mosaic
        )

        #expect(model.whyLine(for: member) == "Your gym, and it's quiet right now")
        #expect(model.whyLine(for: other) == "Moderate right now and close to Home")
        #expect(model.whyLine(for: closed) == "Closed right now, but close to Home")

        model.plannedHour = 20
        #expect(container.rankings.isPlanning)
        #expect(model.subtitle == "Forecast for 8 PM")
        #expect(model.bestPickLabel == "Best pick for 8 PM")
        #expect(model.whyLine(for: member) == "Your gym, and it should be quiet at 8 PM")
        #expect(model.whyLine(for: other) == "Moderate at 8 PM and close to Home")
    }

    @Test func noLocationMeansNoRows() async {
        let (_, model) = await makeModel(fresh: true)
        #expect(model.ranked.isEmpty)
        #expect(model.best == nil)
    }
}
