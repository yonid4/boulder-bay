import Foundation
import Testing

@testable import BoulderBay

@MainActor
struct GymDetailViewModelTests {
    private func makeModel(slug: String, now: Date = wednesday5pm) async -> (AppContainer, GymDetailViewModel) {
        let container = AppContainer(
            auth: MockAuthService.signedIn(as: .preview),
            api: MockAPIClient(now: { now }),
            now: { now }
        )
        await container.gyms.load()
        await container.locations.load()
        await container.memberships.load()
        await container.rankings.refreshIfNeeded()
        let model = GymDetailViewModel(
            slug: slug, service: GymDetailService(api: container.api),
            rankings: container.rankings, memberships: container.memberships,
            locations: container.locations, now: { now }
        )
        await model.load()
        return (container, model)
    }

    @Test func loadsTheDetailAndJoinsTheRanking() async {
        let (_, model) = await makeModel(slug: "mv-belmont")

        #expect(model.state == .loaded)
        #expect(model.gym?.name == "Movement Belmont")
        #expect(model.isMember)
        #expect(model.isOpen)
        #expect(model.nowLabel == "Right now")
        #expect(model.busyPct != nil)
        #expect(model.level != nil)
        #expect(model.travelText?.hasSuffix("min from Home") == true)
        #expect(model.distanceText?.hasSuffix(" mi") == true)
        #expect(model.hoursText == "6 AM – 11 PM")
        #expect(model.openStatusText == "Open until 11 PM")
        #expect(model.dayPassText == "$33")
        #expect(model.monthlyText == "$114")
        #expect(model.rateNote == "Part of the Movement network")
        #expect(model.hasWaiver)
    }

    @Test func barsCoverOpenHoursWithPastCurrentFutureOpacity() async {
        let (_, model) = await makeModel(slug: "mv-belmont")

        #expect(model.bars.map(\.hour) == Array(6..<23))
        #expect(model.bars.first { $0.hour == 16 }?.opacity == 0.3)
        #expect(model.bars.first { $0.hour == 17 }?.opacity == 1)
        #expect(model.bars.first { $0.hour == 17 }?.busyPct == model.busyPct)
        #expect(model.bars.first { $0.hour == 18 }?.opacity == 0.8)
        #expect(model.ticks == [6, 10, 14, 18, 22])
    }

    @Test func bestTimeIsTheQuietestRemainingHour() async {
        let (_, model) = await makeModel(slug: "mv-belmont")

        let best = model.bestWindow
        #expect(best != nil)
        #expect(best!.hour > 17)
        #expect(model.bestTimeText == Format.window(startingAt: best!.hour))
        #expect(model.bestNoteText.hasPrefix(best!.level.label.lowercased()))
    }

    @Test func touchstoneShowsThePeakTier() async {
        let (_, model) = await makeModel(slug: "studio")
        #expect(model.dayPassText == "$25")
        #expect(model.rateNote == "Day pass $30 after 3 PM")
    }

    @Test func plannedHourMovesEverything() async {
        let (container, model) = await makeModel(slug: "mv-belmont")

        container.rankings.plan(hour: 22)
        #expect(model.nowLabel == "At 10 PM")
        #expect(model.isOpen)
        #expect(model.busyPct == BusynessForecast.busyPct(in: model.detail!.forecast, at: 22))
        #expect(model.bestWindow == nil)
        #expect(model.bestTimeText == "Closes soon")
        #expect(model.bars.first { $0.hour == 21 }?.opacity == 0.3)
    }

    @Test func closedGymReadsClosed() async {
        let (_, model) = await makeModel(slug: "mosaic", now: wednesday5pm.addingTimeInterval(-14 * 3600))

        #expect(!model.isOpen)
        #expect(model.busyPct == nil)
        #expect(model.level == nil)
        #expect(model.openStatusText == "Closed")
        // Nothing has happened yet today, so the quietest open hour on the curve wins.
        #expect(model.bestWindow == model.detail?.forecast.min { $0.busyPct < $1.busyPct })
        #expect(model.capacityText == "No live reading")
    }

    @Test func unknownSlugFails() async {
        let (_, model) = await makeModel(slug: "bridges")
        #expect(model.state == .failed(APIError.badStatus(404).localizedDescription))
    }
}
