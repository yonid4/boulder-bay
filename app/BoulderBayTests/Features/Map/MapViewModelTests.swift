import Foundation
import Testing

@testable import BoulderBay

@MainActor
@Suite(.serialized)
struct MapViewModelTests {
    private let host = "map-view-model.test"

    // MARK: Loading

    @Test func loadPublishesTheGymsFromTheAPI() async {
        stub(status: 200, body: GymDecodingTests.payload)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        #expect(model.state == .idle)

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.gyms.map(\.id) == ["dogpatch", "mission"])
        #expect(model.errorMessage == nil)
    }

    @Test func serverErrorLeavesTheListEmptyAndSurfacesAMessage() async {
        stub(status: 500, body: Data())
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.load()

        #expect(model.state == .failed("The server returned an error (500)."))
        #expect(model.gyms.isEmpty)
        #expect(model.errorMessage != nil)
    }

    @Test func expiredSessionGetsItsOwnMessage() async {
        stub(status: 401, body: Data())
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.load()

        #expect(model.state == .failed("Your session has expired. Sign in again."))
    }

    @Test func retryingAfterAFailureRecovers() async {
        let failFirst = LockedBox(true)
        StubURLProtocol.setHandler(forHost: host) { request in
            let shouldFail = failFirst.withValue { value -> Bool in
                defer { value = false }
                return value
            }
            return shouldFail
                ? (Self.response(for: request, status: 500), Data())
                : (Self.response(for: request, status: 200), GymDecodingTests.payload)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.load()
        #expect(model.gyms.isEmpty)

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.gyms.count == 2)
        #expect(model.errorMessage == nil)
    }

    // MARK: Hour

    @Test func selectedHourDefaultsToTheCurrentHourWithMinutesDropped() {
        // 17:59:59 on 2026-09-23 in Los Angeles.
        let model = makeModel(now: Self.date(hour: 17, minute: 59, second: 59))
        #expect(model.selectedHour == 17)
    }

    @Test func dateForHourIsTodayOnTheHour() {
        let model = makeModel(now: Self.date(hour: 17, minute: 59, second: 59))
        #expect(model.date(forHour: 9) == Self.date(hour: 9))
        #expect(model.date(forHour: 0) == Self.date(hour: 0))
        #expect(model.date(forHour: 23) == Self.date(hour: 23))
    }

    @Test func loadRequestsTheSelectedHour() async throws {
        let queries = LockedBox<[String]>([])
        StubURLProtocol.setHandler(forHost: host) { request in
            queries.withValue { $0.append(request.url?.query ?? "") }
            return (Self.response(for: request, status: 200), GymDecodingTests.payload)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel(now: Self.date(hour: 17, minute: 59))
        await model.load()
        model.selectedHour = 9
        await model.load()

        // 17:00 and 09:00 PDT, sent as UTC instants.
        #expect(
            queries.withValue { $0 }
                == ["at=2026-09-24T00:00:00Z", "at=2026-09-23T16:00:00Z"]
        )
        #expect(model.state == .loaded)
    }

    // MARK: Selection

    @Test func selectionResolvesToAGymAndClears() async {
        stub(status: 200, body: GymDecodingTests.payload)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.load()
        #expect(model.selectedGym == nil)

        model.select(model.gyms[1])
        #expect(model.selectedGymID == "mission")
        #expect(model.selectedGym?.name == "Mission Cliffs")

        model.clearSelection()
        #expect(model.selectedGym == nil)
        #expect(model.selectedGymID == nil)
    }

    @Test func reloadDropsASelectionThatNoLongerExists() async {
        let firstLoad = LockedBox(true)
        StubURLProtocol.setHandler(forHost: host) { request in
            let full = firstLoad.withValue { value -> Bool in
                defer { value = false }
                return value
            }
            return (
                Self.response(for: request, status: 200),
                full ? GymDecodingTests.payload : Self.dogpatchOnlyPayload
            )
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.load()
        model.select(model.gyms[1])
        #expect(model.selectedGymID == "mission")

        await model.load()

        #expect(model.gyms.map(\.id) == ["dogpatch"])
        #expect(model.selectedGymID == nil)
    }

    // MARK: Labels

    @Test func openStateLabelReadsFromBusyness() {
        #expect(MapViewModel.openStateLabel(for: Self.gym(isOpen: true)) == "Open")
        #expect(MapViewModel.openStateLabel(for: Self.gym(isOpen: false)) == "Closed")
    }

    // MARK: Region

    @Test func regionIsNilWithoutGyms() {
        #expect(MapViewModel.region(fitting: []) == nil)
    }

    @Test func regionSpansEveryGymAndCentersBetweenThem() throws {
        let region = try #require(
            MapViewModel.region(fitting: [
                Self.gym(slug: "south", latitude: 37.0, longitude: -122.5),
                Self.gym(slug: "north", latitude: 38.0, longitude: -121.5),
            ])
        )

        #expect(abs(region.center.latitude - 37.5) < 0.0001)
        #expect(abs(region.center.longitude - -122.0) < 0.0001)
        // 1° of spread, padded so the outermost pins aren't flush against the edge.
        #expect(region.span.latitudeDelta > 1.0)
        #expect(region.span.longitudeDelta > 1.0)
    }

    @Test func singleGymGetsTheMinimumSpanNotAZeroSpan() throws {
        let region = try #require(
            MapViewModel.region(fitting: [Self.gym(latitude: 37.7567, longitude: -122.3903)])
        )

        #expect(region.center.latitude == 37.7567)
        #expect(region.center.longitude == -122.3903)
        #expect(region.span.latitudeDelta == 0.02)
        #expect(region.span.longitudeDelta == 0.02)
    }

    // MARK: Helpers

    private func makeModel(now: Date = .now) -> MapViewModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return MapViewModel(
            apiClient: APIClient(
                baseURL: URL(string: "https://\(host)")!,
                session: URLSession(configuration: configuration),
                accessToken: { "test-token" }
            ),
            calendar: Self.calendar,
            now: { now }
        )
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// 2026-09-23 at the given local time in `calendar`'s timezone.
    private static func date(hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(
                year: 2026, month: 9, day: 23, hour: hour, minute: minute, second: second
            )
        )!
    }

    private func stub(status: Int, body: Data) {
        StubURLProtocol.setHandler(forHost: host) { request in
            (Self.response(for: request, status: status), body)
        }
    }

    nonisolated private static func response(
        for request: URLRequest, status: Int
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    nonisolated private static let dogpatchOnlyPayload = Data(
        """
        {"data": [
            {
                "slug": "dogpatch",
                "name": "Dogpatch Boulders",
                "brand": "touchstone",
                "city": "San Francisco",
                "latitude": 37.7567,
                "longitude": -122.3903,
                "logo_url": null,
                "busyness": {
                    "at": "2026-09-13T18:00:00Z",
                    "is_open": true,
                    "busy_pct": null,
                    "level": null,
                    "source": null
                }
            }
        ]}
        """.utf8
    )

    private static func gym(
        slug: String = "dogpatch",
        latitude: Double = 37.7567,
        longitude: Double = -122.3903,
        isOpen: Bool = true
    ) -> Gym {
        Gym(
            slug: slug,
            name: "Dogpatch Boulders",
            brand: .touchstone,
            city: "San Francisco",
            latitude: latitude,
            longitude: longitude,
            logoUrl: nil,
            busyness: ResolvedBusyness(
                at: Date(timeIntervalSince1970: 1_789_322_400),
                isOpen: isOpen,
                busyPct: nil,
                level: nil,
                source: nil
            )
        )
    }
}
