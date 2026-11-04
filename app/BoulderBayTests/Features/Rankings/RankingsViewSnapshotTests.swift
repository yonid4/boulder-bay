import SnapshotTesting
import SwiftUI
import Testing

@testable import BoulderBay

/// Reference images live in `__Snapshots__/`. To re-record after an intended visual change,
/// delete the affected PNGs and run the tests once; they fail while recording, then pass.
@MainActor
@Suite
struct RankingsViewSnapshotTests {
    private static let home = SavedLocation(
        id: UUID(uuidString: "d16878be-c4bc-462f-8929-c464b6a5efad")!,
        label: "Home",
        address: nil,
        latitude: 37.8,
        longitude: -122.2,
        isDefault: true,
        kind: .home
    )

    private static let ranked = [
        row(1, slug: "mosaic", name: "Mosaic Boulders", city: "Oakland", level: .quiet, percent: 28, minutes: 12.4),
        row(2, slug: "berkeley", name: "Berkeley Boulders", city: "Berkeley", level: .moderate, percent: 52, minutes: 18),
        row(3, slug: "dogpatch", name: "Dogpatch Boulders", city: "San Francisco", level: .packed, percent: 81, minutes: 25.2),
        row(4, slug: "long", name: "Touchstone Mission Cliffs Bouldering and Fitness", city: "San Francisco", level: nil, percent: nil, minutes: 31),
    ]

    @Test func nonMemberBestPickNow() {
        assertScreen(content(.loaded(rankings(Self.ranked), refreshError: nil)))
    }

    @Test func memberBestPickAtAnotherHour() {
        assertScreen(content(
            .loaded(rankings(Self.ranked), refreshError: nil),
            memberships: ["mosaic", "dogpatch"],
            hour: 19,
            isNow: false
        ))
    }

    /// A long drive and a packed gym give no reason beyond being the best on offer.
    @Test func packedAndFarBestPick() {
        let best = Self.row(
            1, slug: "dogpatch", name: "Dogpatch Boulders", city: "San Francisco", level: .packed,
            percent: 81, minutes: 43
        )
        assertScreen(content(
            .loaded(rankings([best]), refreshError: nil), hour: 18, isNow: false
        ))
    }

    @Test func oneGymOnly() {
        assertScreen(content(.loaded(rankings(Array(Self.ranked.prefix(1))), refreshError: nil)))
    }

    @Test func emptyList() {
        assertScreen(content(.loaded(rankings([]), refreshError: nil), hour: 23, isNow: false))
    }

    @Test func loading() {
        assertScreen(content(.loading))
    }

    @Test func failed() {
        assertScreen(content(.failed("The server returned an error (500).")))
    }

    @Test func failedRefreshKeepsTheList() {
        assertScreen(content(.loaded(
            rankings(Self.ranked), refreshError: "Couldn't reach the server. Check your connection."
        )))
    }

    @Test func header() {
        assertHeader(isTimeOpen: false)
    }

    @Test func headerWithTheSliderOpen() {
        assertHeader(isTimeOpen: true)
    }

    // MARK: Helpers

    private func rankings(_ rows: [RankedGym]) -> Rankings {
        Rankings(at: Date(timeIntervalSince1970: 1_789_322_400), location: Self.home, rankedGyms: rows)
    }

    private func content(
        _ phase: RankingsViewModel.Phase,
        memberships: Set<String> = [],
        hour: Int = 17,
        isNow: Bool = true
    ) -> some View {
        RankingsContent(
            phase: phase,
            memberships: memberships,
            place: "Home",
            hour: hour,
            isNow: isNow,
            onRefresh: {},
            onOpenGym: { _ in }
        )
        .background(Theme.background)
    }

    private func assertScreen(
        _ view: some View,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        assertSnapshot(
            of: view.frame(width: 393, height: 620),
            // Small rendering differences between simulator OS versions shouldn't fail CI.
            as: .image(perceptualPrecision: 0.98, layout: .sizeThatFits),
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }

    private func assertHeader(
        isTimeOpen: Bool,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let header = RankingsHeader(
            timeLabel: "Forecast for 7 PM",
            timeChip: "7 PM",
            locations: [Self.home],
            selected: Self.home,
            isTimeOpen: .constant(isTimeOpen),
            sliderHour: .constant(19),
            onSelectLocation: { _ in },
            onHourEditingChanged: { _ in }
        )
        assertSnapshot(
            of: header.padding(.bottom, 16).frame(width: 393).background(Theme.background),
            as: .image(perceptualPrecision: 0.98, layout: .sizeThatFits),
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }

    private static func row(
        _ rank: Int, slug: String, name: String, city: String, level: BusynessLevel?, percent: Int?,
        minutes: Double
    ) -> RankedGym {
        RankedGym(
            rank: rank,
            score: Double(90 - rank),
            travelMinutes: minutes,
            gym: Gym(
                slug: slug, name: name, brand: .independent, city: city, latitude: 37.8,
                longitude: -122.27, logoUrl: nil, isMember: false,
                busyness: ResolvedBusyness(
                    at: Date(timeIntervalSince1970: 1_789_322_400), isOpen: true, busyPct: percent,
                    level: level, source: .forecast
                )
            )
        )
    }
}
