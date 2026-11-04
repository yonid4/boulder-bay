import Foundation
import MapKit
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

    @Test func conflictShowsTheServersMessageAsItIs() async {
        stub(status: 409, body: Data(#"{"detail": "Add a place first"}"#.utf8))
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.load()

        #expect(model.state == .failed("Add a place first"))
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

    @Test func loadRequestsTheSelectedHour() async throws {
        let queries = LockedBox<[String]>([])
        StubURLProtocol.setHandler(forHost: host) { request in
            queries.withValue { $0.append(request.url?.query ?? "") }
            return (Self.response(for: request, status: 200), GymDecodingTests.payload)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel(now: Self.date(hour: 17, minute: 59))
        await model.load()
        model.appModel.selectedHour = 9
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

    // MARK: Appearing again

    @Test func appearingAgainKeepsAListLoadedForThisHour() async {
        let requests = countRequests(status: { _ in 200 })
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(requests.withValue { $0 } == 1)
        #expect(model.gyms.count == 2)
    }

    @Test func appearingAgainLoadsWhenTheListIsForAnotherHour() async {
        let requests = countRequests(status: { _ in 200 })
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.loadIfNeeded()
        model.appModel.selectedHour = (model.appModel.selectedHour + 2) % 24
        await model.loadIfNeeded()

        #expect(requests.withValue { $0 } == 2)
    }

    @Test func appearingAgainRetriesAFailedLoad() async {
        let requests = countRequests(status: { $0 == 1 ? 500 : 200 })
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.loadIfNeeded()
        #expect(model.errorMessage != nil)

        await model.loadIfNeeded()

        #expect(requests.withValue { $0 } == 2)
        #expect(model.state == .loaded)
    }

    // MARK: Camera

    @Test func theFirstFitWaitsForGymsAndHappensOnce() async {
        stub(status: 200, body: GymDecodingTests.payload)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        #expect(model.regionForFirstFit() == nil)

        await model.load()

        #expect(model.regionForFirstFit() != nil)
        #expect(model.regionForFirstFit() == nil)
    }

    @Test func aFirstLoadThatFailedStillFitsOnceARetryBringsGyms() async {
        _ = countRequests(status: { $0 == 1 ? 500 : 200 })
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.load()
        #expect(model.regionForFirstFit() == nil)

        await model.load()

        #expect(model.regionForFirstFit() != nil)
    }

    @Test func theCameraIsOnlyRememberedOnceItHasFitTheGyms() async {
        stub(status: 200, body: GymDecodingTests.payload)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        let moved = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.8, longitude: -122.3),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )

        // MapKit reports the default region as it settles, before there are gyms.
        model.cameraMoved(to: .bayArea)
        #expect(model.cameraRegion == nil)

        await model.load()
        let fit = model.regionForFirstFit()
        #expect(fit != nil)
        #expect(model.cameraRegion?.center.latitude == fit?.center.latitude)

        model.cameraMoved(to: moved)

        #expect(model.cameraRegion?.center.latitude == 37.8)
        #expect(model.cameraRegion?.span.longitudeDelta == 0.02)
        // Having been moved, it never jumps back to fitting the gyms.
        #expect(model.regionForFirstFit() == nil)
    }

    // MARK: Shared list

    @Test func theGymsAreTheAppModels() async {
        stub(status: 200, body: GymDecodingTests.payload)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.load()

        #expect(model.appModel.gyms.map(\.id) == ["dogpatch", "mission"])
        #expect(model.appModel.gymsState == .loaded)
    }

    // MARK: Pin order

    @Test func memberPinsSitAboveTheOthers() {
        let member = MapViewModel.zPriority(isSelected: false, isMember: true)
        let other = MapViewModel.zPriority(isSelected: false, isMember: false)

        #expect(member.rawValue > other.rawValue)
    }

    @Test func theSelectedPinSitsAboveEveryMember() {
        let member = MapViewModel.zPriority(isSelected: false, isMember: true).rawValue

        #expect(MapViewModel.zPriority(isSelected: true, isMember: false).rawValue > member)
        #expect(MapViewModel.zPriority(isSelected: true, isMember: true).rawValue > member)
    }

    // MARK: Labels

    @Test func busynessLabelFallsBackToOpenStateWithoutAReading() {
        #expect(MapViewModel.busynessLabel(for: Self.gym(isOpen: true)) == "Open")
        #expect(MapViewModel.busynessLabel(for: Self.gym(isOpen: false)) == "Closed")
    }

    @Test func busynessLabelLeadsWithTheLevelThenThePercent() {
        let gym = Self.gym(busyPct: 32, level: .quiet, source: .forecast)
        #expect(MapViewModel.busynessLabel(for: gym) == "Quiet · 32%")
    }

    @Test func busynessLabelTagsALiveReading() {
        let gym = Self.gym(busyPct: 81, level: .packed, source: .live)
        #expect(MapViewModel.busynessLabel(for: gym) == "Packed · 81% · Live")
    }

    @Test func busynessLabelDoesNotTagAnObservedPastHour() {
        let gym = Self.gym(busyPct: 55, level: .moderate, source: .observed)
        #expect(MapViewModel.busynessLabel(for: gym) == "Moderate · 55%")
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
        let apiClient = APIClient(
            baseURL: URL(string: "https://\(host)")!,
            session: URLSession(configuration: configuration),
            accessToken: { "test-token" }
        )
        return MapViewModel(
            apiClient: apiClient,
            appModel: AppModel(apiClient: apiClient, calendar: Self.calendar, now: { now })
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

    /// Answers each request with the gyms and the status for its number, counting from 1.
    private func countRequests(status: @escaping @Sendable (Int) -> Int) -> LockedBox<Int> {
        let requests = LockedBox(0)
        StubURLProtocol.setHandler(forHost: host) { request in
            let count = requests.withValue { value -> Int in
                value += 1
                return value
            }
            return (
                Self.response(for: request, status: status(count)), GymDecodingTests.payload
            )
        }
        return requests
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
                "is_member": false,
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
        isOpen: Bool = true,
        busyPct: Int? = nil,
        level: BusynessLevel? = nil,
        source: BusynessSource? = nil
    ) -> Gym {
        Gym(
            slug: slug,
            name: "Dogpatch Boulders",
            brand: .touchstone,
            city: "San Francisco",
            latitude: latitude,
            longitude: longitude,
            logoUrl: nil,
            isMember: false,
            busyness: ResolvedBusyness(
                at: Date(timeIntervalSince1970: 1_789_322_400),
                isOpen: isOpen,
                busyPct: busyPct,
                level: level,
                source: source
            )
        )
    }
}
