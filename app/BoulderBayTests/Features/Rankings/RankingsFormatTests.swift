import Foundation
import Testing

@testable import BoulderBay

@Suite
struct RankingsFormatTests {
    @Test func theButtonAndHeaderNameTheHour() {
        #expect(RankingsFormat.bestButton(hour: 17, isNow: true) == "Best right now")
        #expect(RankingsFormat.bestButton(hour: 19, isNow: false) == "Best at 7 PM")
        #expect(RankingsFormat.timeLabel(hour: 17, isNow: true) == "Live, 5 PM")
        #expect(RankingsFormat.timeLabel(hour: 19, isNow: false) == "Forecast for 7 PM")
        #expect(RankingsFormat.timeChip(hour: 17, isNow: true) == "Now")
        #expect(RankingsFormat.timeChip(hour: 0, isNow: false) == "12 AM")
        #expect(RankingsFormat.bestPickTitle(hour: 17, isNow: true) == "Best pick right now")
        #expect(RankingsFormat.bestPickTitle(hour: 19, isNow: false) == "Best pick for 7 PM")
    }

    @Test func anEmptyListSaysSoForTheHour() {
        #expect(
            RankingsFormat.nothingOpen(near: "Home", hour: 23, isNow: false)
                == "Nothing open near Home at 11 PM"
        )
        #expect(
            RankingsFormat.nothingOpen(near: "Home", hour: 9, isNow: true)
                == "Nothing open near Home right now"
        )
        #expect(
            RankingsFormat.emptyTitle(near: "Work", hour: 23, isNow: false)
                == "No gym near Work is open at 11 PM"
        )
    }

    @Test func theWhyLeadsWithMembership() {
        let gym = Self.gym(level: .quiet, percent: 28)
        #expect(
            RankingsFormat.why(gym: gym, isMember: true, place: "Home", hour: 17, isNow: true)
                == "Your gym, and it's quiet right now"
        )
        #expect(
            RankingsFormat.why(gym: gym, isMember: true, place: "Home", hour: 19, isNow: false)
                == "Your gym, and it should be quiet at 7 PM"
        )
        #expect(
            RankingsFormat.why(gym: gym, isMember: false, place: "Home", hour: 17, isNow: true)
                == "Quiet right now and close to Home"
        )
        #expect(
            RankingsFormat.why(gym: gym, isMember: false, place: "Work", hour: 19, isNow: false)
                == "Quiet at 7 PM and close to Work"
        )
    }

    @Test func aGymWithNoReadingReadsAsOpen() {
        let gym = Self.gym(level: nil, percent: nil)
        #expect(RankingsFormat.busynessWord(gym.busyness) == "Open")
        #expect(
            RankingsFormat.why(gym: gym, isMember: false, place: "Home", hour: 17, isNow: true)
                == "Open right now and close to Home"
        )
    }

    @Test func travelRoundsAndNeverSaysZero() {
        #expect(RankingsFormat.travel(minutes: 17.5) == "18 min away")
        #expect(RankingsFormat.travel(minutes: 0.7) == "1 min away")
        #expect(RankingsFormat.travel(minutes: 0) == "1 min away")
    }

    private static func gym(level: BusynessLevel?, percent: Int?) -> Gym {
        Gym(
            slug: "mosaic", name: "Mosaic Boulders", brand: .independent, city: "Oakland",
            latitude: 37.8, longitude: -122.27, logoUrl: nil, isMember: false,
            busyness: ResolvedBusyness(
                at: Date(timeIntervalSince1970: 1_789_322_400), isOpen: true, busyPct: percent,
                level: level, source: .forecast
            )
        )
    }
}
