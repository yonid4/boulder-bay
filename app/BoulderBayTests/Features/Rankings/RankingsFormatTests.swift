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
        #expect(why(.quiet, minutes: 12, member: true) == "Your gym, and it's quiet right now")
        #expect(why(.quiet, minutes: 54, member: true) == "Your gym, and it's quiet right now")
        #expect(
            why(.moderate, minutes: 12, member: true, hour: 19, isNow: false)
                == "Your gym, and it should be moderately busy at 7 PM"
        )
    }

    @Test func aPackedMemberGymDoesNotOfferTheCrowdAsAReason() {
        #expect(
            why(.packed, minutes: 43, member: true, hour: 18, isNow: false)
                == "Your gym, and the best of what's open at 6 PM"
        )
    }

    @Test func closeIsOnlySaidOfAShortDrive() {
        #expect(why(.quiet, minutes: 12) == "Quiet right now and close to Home")
        #expect(why(.quiet, minutes: 20) == "Quiet right now and close to Home")
        #expect(why(.quiet, minutes: 20.5) == "Quiet right now")
        #expect(why(.quiet, minutes: 54) == "Quiet right now")
        #expect(
            why(.moderate, minutes: 12, hour: 19, isNow: false)
                == "Moderately busy at 7 PM and close to Home"
        )
    }

    @Test func aPackedGymIsOnlyRecommendedForWhatElseIsTrue() {
        #expect(why(.packed, minutes: 12) == "Close to Home")
        #expect(why(.packed, minutes: 43) == "The best of what's open right now")
        #expect(
            why(.packed, minutes: 43, hour: 18, isNow: false) == "The best of what's open at 6 PM"
        )
    }

    @Test func aGymWithNoReadingReadsAsOpen() {
        #expect(RankingsFormat.busynessWord(Self.ranked(level: nil, minutes: 12).gym.busyness) == "Open")
        #expect(why(nil, minutes: 12) == "Open right now and close to Home")
        #expect(why(nil, minutes: 54) == "Open right now")
    }

    @Test func travelRoundsAndNeverSaysZero() {
        #expect(RankingsFormat.travel(minutes: 17.5) == "18 min away")
        #expect(RankingsFormat.travel(minutes: 0.7) == "1 min away")
        #expect(RankingsFormat.travel(minutes: 0) == "1 min away")
    }

    private func why(
        _ level: BusynessLevel?,
        minutes: Double,
        member: Bool = false,
        hour: Int = 17,
        isNow: Bool = true
    ) -> String {
        RankingsFormat.why(
            rankedGym: Self.ranked(level: level, minutes: minutes),
            isMember: member,
            place: "Home",
            hour: hour,
            isNow: isNow
        )
    }

    private static func ranked(level: BusynessLevel?, minutes: Double) -> RankedGym {
        RankedGym(
            rank: 1,
            score: 80,
            travelMinutes: minutes,
            gym: Gym(
                slug: "mosaic", name: "Mosaic Boulders", brand: .independent, city: "Oakland",
                latitude: 37.8, longitude: -122.27, logoUrl: nil, isMember: false,
                busyness: ResolvedBusyness(
                    at: Date(timeIntervalSince1970: 1_789_322_400), isOpen: true,
                    busyPct: level == nil ? nil : 50, level: level, source: .forecast
                )
            )
        )
    }
}
