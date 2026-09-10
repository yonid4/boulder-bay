import Foundation
import Testing

@testable import BoulderBay

@MainActor
struct GymsViewModelTests {
    private func makeModel() async -> (AppContainer, GymsViewModel) {
        let container = AppContainer(
            auth: MockAuthService.signedIn(as: .preview),
            api: MockAPIClient(now: { wednesday5pm }),
            now: { wednesday5pm }
        )
        await container.locations.load()
        let model = GymsViewModel(
            gyms: container.gyms, memberships: container.memberships, rankings: container.rankings
        )
        await model.load()
        await container.rankings.refreshIfNeeded()
        return (container, model)
    }

    @Test func searchMatchesNameCityAndBrand() async {
        let (_, model) = await makeModel()
        #expect(!model.hasQuery)
        #expect(model.results.isEmpty)

        model.query = "benchmark"
        #expect(model.results.map(\.slug) == ["bm-sf", "bm-berkeley"])

        model.query = " Berkeley "
        #expect(model.results.map(\.slug) == ["ironworks", "the-oaks", "bm-berkeley", "mosaic"])

        model.query = "Touchstone"
        #expect(model.results.count == 8)

        model.query = "bridges"
        #expect(model.noResults)

        model.clearQuery()
        #expect(!model.hasQuery)
    }

    @Test func memberListAndCountFollowTheStore() async {
        let (_, model) = await makeModel()
        #expect(model.memberGyms.map(\.slug) == ["mv-sf", "mv-belmont", "mv-mountain-view", "mv-santa-clara"])
        #expect(model.memberCountLabel == "4 gyms")
    }

    @Test func toggleAddsRemovesAndStalesRankings() async {
        let (container, model) = await makeModel()
        let fetchesBefore = container.rankings.rankings != nil
        #expect(fetchesBefore)

        await model.toggle(PreviewData.mosaic)
        #expect(model.isMember(PreviewData.mosaic))
        #expect(model.memberGyms.map(\.slug).contains("mosaic"))
        #expect(model.memberCountLabel == "5 gyms")

        await container.rankings.refreshIfNeeded()
        #expect(container.rankings.entry(for: "mosaic")?.isMember == true)

        for gym in model.memberGyms { await model.toggle(gym) }
        #expect(model.memberGyms.isEmpty)
        #expect(model.memberCountLabel == "None yet")

        await model.toggle(PreviewData.belmont)
        #expect(model.memberCountLabel == "1 gym")
    }
}
