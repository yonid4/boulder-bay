import Foundation
import Testing

@testable import BoulderBay

@MainActor
@Suite(.serialized)
struct AppModelTests {
    private let host = "app-model.test"

    // MARK: Bootstrap

    @Test func bootstrapLoadsProfileLocationsAndMemberships() async {
        stubAccount()
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        #expect(model.state == .idle)

        await model.bootstrap()

        #expect(model.state == .loaded)
        #expect(model.profile?.displayName == "Alex Rivera")
        #expect(model.locations.map(\.id) == [Self.homeID, Self.officeID])
        #expect(model.memberships == ["dogpatch", "mission"])
    }

    @Test func bootstrapSelectsTheDefaultLocation() async {
        // The default is the second place, so a "first place" shortcut would fail here.
        stubAccount(locations: Self.locationsPayload(defaultID: Self.officeID))
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()

        #expect(model.selectedLocationID == Self.officeID)
        #expect(model.selectedLocation?.label == "Office")
    }

    @Test func bootstrapWithoutPlacesSelectsNothing() async {
        stubAccount(locations: Data(#"{"data": []}"#.utf8))
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()

        #expect(model.state == .loaded)
        #expect(model.locations.isEmpty)
        #expect(model.selectedLocationID == nil)
        #expect(model.selectedLocation == nil)
    }

    @Test func bootstrapFailureSurfacesAMessageAndKeepsNoPartialData() async {
        stubAccount(membershipsStatus: 500)
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()

        #expect(model.state == .failed("The server returned an error (500)."))
        #expect(model.profile == nil)
        #expect(model.locations.isEmpty)
        #expect(model.memberships.isEmpty)
    }

    @Test func bootstrapRetriesAfterAFailure() async {
        let failFirst = LockedBox(true)
        StubURLProtocol.setHandler(forHost: host) { request in
            if request.url?.path == "/api/me" {
                let shouldFail = failFirst.withValue { value -> Bool in
                    defer { value = false }
                    return value
                }
                if shouldFail { return (Self.response(for: request, status: 500), Data()) }
            }
            return Self.accountResponse(for: request)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()
        #expect(model.state == .failed("The server returned an error (500)."))

        await model.bootstrap()

        #expect(model.state == .loaded)
        #expect(model.profile?.displayName == "Alex Rivera")
    }

    // MARK: Location selection

    @Test func selectingALocationChangesTheSelection() async {
        stubAccount()
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()
        model.selectLocation(id: Self.officeID)

        #expect(model.selectedLocation?.label == "Office")
    }

    @Test func selectingAnUnknownLocationIsIgnored() async {
        stubAccount()
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()
        model.selectLocation(id: UUID())

        #expect(model.selectedLocationID == Self.homeID)
    }

    @Test func reloadingLocationsKeepsASelectionThatStillExists() async throws {
        stubAccount()
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()
        model.selectLocation(id: Self.officeID)

        try await model.reloadLocations()

        #expect(model.selectedLocationID == Self.officeID)
    }

    @Test func reloadingLocationsFallsBackToTheDefaultWhenTheSelectionIsGone() async throws {
        let locations = LockedBox(Self.locationsPayload(defaultID: Self.homeID))
        StubURLProtocol.setHandler(forHost: host) { request in
            guard request.url?.path == "/api/me/locations" else {
                return Self.accountResponse(for: request)
            }
            return (Self.response(for: request, status: 200), locations.withValue { $0 })
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()
        model.selectLocation(id: Self.officeID)

        // The office was deleted elsewhere; only home remains.
        locations.withValue { $0 = Self.locationsPayload(defaultID: Self.homeID, includeOffice: false) }
        try await model.reloadLocations()

        #expect(model.locations.map(\.id) == [Self.homeID])
        #expect(model.selectedLocationID == Self.homeID)
    }

    @Test func reloadingLocationsRethrowsAndKeepsTheOldList() async {
        let failLocations = LockedBox(false)
        StubURLProtocol.setHandler(forHost: host) { request in
            if request.url?.path == "/api/me/locations", failLocations.withValue({ $0 }) {
                return (Self.response(for: request, status: 500), Data())
            }
            return Self.accountResponse(for: request)
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()
        failLocations.withValue { $0 = true }

        await #expect(throws: APIError.badStatus(500)) { try await model.reloadLocations() }
        #expect(model.locations.count == 2)
        #expect(model.selectedLocationID == Self.homeID)
    }

    // MARK: Memberships

    @Test func joiningAGymFlipsTheSetBeforeTheServerAnswers() async {
        let release = DispatchSemaphore(value: 0)
        let requests = LockedBox<[String]>([])
        StubURLProtocol.setHandler(forHost: host) { request in
            guard request.url?.path.hasPrefix("/api/me/memberships/") == true else {
                return Self.accountResponse(for: request)
            }
            requests.withValue { $0.append("\(request.httpMethod!) \(request.url!.path)") }
            release.wait()
            return (Self.response(for: request, status: 204), Data())
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()

        let toggle = Task { await model.toggleMembership(gymSlug: "berkeley") }
        await waitUntil { model.pendingMemberships.contains("berkeley") }

        #expect(model.memberships.contains("berkeley"))
        release.signal()
        await toggle.value

        #expect(model.memberships.contains("berkeley"))
        #expect(model.pendingMemberships.isEmpty)
        #expect(model.membershipError == nil)
        #expect(requests.withValue { $0 } == ["POST /api/me/memberships/berkeley"])
    }

    @Test func leavingAGymSendsADelete() async {
        let requests = LockedBox<[String]>([])
        StubURLProtocol.setHandler(forHost: host) { request in
            guard request.url?.path.hasPrefix("/api/me/memberships/") == true else {
                return Self.accountResponse(for: request)
            }
            requests.withValue { $0.append("\(request.httpMethod!) \(request.url!.path)") }
            return (Self.response(for: request, status: 204), Data())
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()
        await model.toggleMembership(gymSlug: "mission")

        #expect(model.memberships == ["dogpatch"])
        #expect(requests.withValue { $0 } == ["DELETE /api/me/memberships/mission"])
    }

    @Test func aFailedToggleRollsBackAndSurfacesAMessage() async {
        StubURLProtocol.setHandler(forHost: host) { request in
            guard request.url?.path.hasPrefix("/api/me/memberships/") == true else {
                return Self.accountResponse(for: request)
            }
            return (Self.response(for: request, status: 500), Data())
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()

        await model.toggleMembership(gymSlug: "berkeley")
        #expect(model.memberships == ["dogpatch", "mission"])
        #expect(model.membershipError == "The server returned an error (500).")

        await model.toggleMembership(gymSlug: "mission")
        #expect(model.memberships == ["dogpatch", "mission"])
        #expect(model.pendingMemberships.isEmpty)
    }

    @Test func aConflictShowsTheServersMessageAsItIs() async {
        StubURLProtocol.setHandler(forHost: host) { request in
            guard request.url?.path.hasPrefix("/api/me/memberships/") == true else {
                return Self.accountResponse(for: request)
            }
            return (Self.response(for: request, status: 409), Data(#"{"detail": "Nope"}"#.utf8))
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()
        await model.toggleMembership(gymSlug: "berkeley")

        #expect(model.membershipError == "Nope")
    }

    @Test func aSecondToggleWhileOneIsInFlightIsIgnored() async {
        let release = DispatchSemaphore(value: 0)
        let requestCount = LockedBox(0)
        StubURLProtocol.setHandler(forHost: host) { request in
            guard request.url?.path.hasPrefix("/api/me/memberships/") == true else {
                return Self.accountResponse(for: request)
            }
            requestCount.withValue { $0 += 1 }
            release.wait()
            return (Self.response(for: request, status: 204), Data())
        }
        defer { StubURLProtocol.removeHandler(forHost: host) }

        let model = makeModel()
        await model.bootstrap()

        let first = Task { await model.toggleMembership(gymSlug: "berkeley") }
        await waitUntil { model.pendingMemberships.contains("berkeley") }
        await model.toggleMembership(gymSlug: "berkeley")
        release.signal()
        await first.value

        #expect(model.memberships.contains("berkeley"))
        #expect(requestCount.withValue { $0 } == 1)
    }

    // MARK: Hour

    @Test func selectedHourDefaultsToTheCurrentHourWithMinutesDropped() {
        let model = makeModel(now: Self.date(hour: 17, minute: 59, second: 59))
        #expect(model.selectedHour == 17)
        #expect(model.isSelectedHourNow)
    }

    @Test func aDifferentHourIsNotNow() {
        let model = makeModel(now: Self.date(hour: 17, minute: 30))
        model.selectedHour = 19
        #expect(!model.isSelectedHourNow)
        model.selectedHour = 9
        #expect(!model.isSelectedHourNow)
    }

    @Test func dateForHourIsTodayOnTheHour() {
        let model = makeModel(now: Self.date(hour: 17, minute: 59, second: 59))
        #expect(model.date(forHour: 9) == Self.date(hour: 9))
        #expect(model.date(forHour: 0) == Self.date(hour: 0))
        #expect(model.date(forHour: 23) == Self.date(hour: 23))
    }

    // MARK: Live refresh

    @Test func aPollPingRefreshesAfterTheJitterWhenTheHourIsNow() async {
        let (pings, continuation) = AsyncStream<Void>.makeStream()
        let delays = LockedBox<[Duration]>([])
        let model = makeModel(
            pollPings: { pings },
            refreshDelay: { .seconds(7) },
            sleep: { duration in delays.withValue { $0.append(duration) } }
        )

        let listening = Task { await model.listenForPolls() }
        continuation.yield()
        continuation.yield()
        continuation.finish()
        await listening.value

        #expect(model.liveRefreshCount == 2)
        #expect(delays.withValue { $0 } == [.seconds(7), .seconds(7)])
    }

    @Test func aPollPingIsSkippedWhenAnotherHourIsSelected() async {
        let (pings, continuation) = AsyncStream<Void>.makeStream()
        let sleeps = LockedBox(0)
        let model = makeModel(
            pollPings: { pings },
            refreshDelay: { .zero },
            sleep: { _ in sleeps.withValue { $0 += 1 } }
        )
        model.selectedHour = (model.selectedHour + 2) % 24

        let listening = Task { await model.listenForPolls() }
        continuation.yield()
        continuation.finish()
        await listening.value

        #expect(model.liveRefreshCount == 0)
        #expect(sleeps.withValue { $0 } == 0)
    }

    @Test func aPollPingIsDroppedWhenTheHourChangesDuringTheJitter() async {
        let (pings, continuation) = AsyncStream<Void>.makeStream()
        // The user drags the slider to another hour while the refetch waits out its jitter.
        let modelBox = LockedBox<AppModel?>(nil)
        let model = makeModel(
            pollPings: { pings },
            refreshDelay: { .seconds(5) },
            sleep: { _ in
                guard let model = modelBox.withValue({ $0 }) else { return }
                await MainActor.run { model.selectedHour = (model.selectedHour + 2) % 24 }
            }
        )
        modelBox.withValue { $0 = model }

        let listening = Task { await model.listenForPolls() }
        continuation.yield()
        continuation.finish()
        await listening.value

        #expect(model.liveRefreshCount == 0)
    }

    @Test func listeningStopsWhenCancelled() async {
        let (pings, continuation) = AsyncStream<Void>.makeStream()
        let terminated = LockedBox(false)
        continuation.onTermination = { _ in terminated.withValue { $0 = true } }
        let model = makeModel(pollPings: { pings })

        let listening = Task { await model.listenForPolls() }
        await Task.yield()
        listening.cancel()
        await listening.value

        #expect(terminated.withValue { $0 })
    }

    // MARK: Helpers

    private func makeModel(
        now: Date = .now,
        pollPings: @escaping @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } },
        refreshDelay: @escaping @Sendable () -> Duration = { .zero },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
    ) -> AppModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return AppModel(
            apiClient: APIClient(
                baseURL: URL(string: "https://\(host)")!,
                session: URLSession(configuration: configuration),
                accessToken: { "test-token" }
            ),
            calendar: Self.calendar,
            now: { now },
            pollPings: pollPings,
            refreshDelay: refreshDelay,
            sleep: sleep
        )
    }

    /// Yields to the model's tasks until `condition` holds, failing after about a second.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Condition never became true")
    }

    private func stubAccount(
        locations: Data = AppModelTests.locationsPayload(defaultID: AppModelTests.homeID),
        membershipsStatus: Int = 200
    ) {
        StubURLProtocol.setHandler(forHost: host) { request in
            switch request.url?.path {
            case "/api/me/locations":
                return (Self.response(for: request, status: 200), locations)
            case "/api/me/memberships" where membershipsStatus != 200:
                return (Self.response(for: request, status: membershipsStatus), Data())
            default:
                return Self.accountResponse(for: request)
            }
        }
    }

    /// The happy-path answer for each of the three bootstrap routes.
    nonisolated private static func accountResponse(
        for request: URLRequest
    ) -> (HTTPURLResponse, Data) {
        switch request.url?.path {
        case "/api/me":
            (response(for: request, status: 200), profilePayload)
        case "/api/me/locations":
            (response(for: request, status: 200), locationsPayload(defaultID: homeID))
        case "/api/me/memberships":
            (response(for: request, status: 200), membershipsPayload)
        default:
            (response(for: request, status: 404), Data())
        }
    }

    nonisolated private static func response(
        for request: URLRequest, status: Int
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
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

    nonisolated private static let homeID = UUID(
        uuidString: "3f2a9c1e-8b7d-4e6f-9a01-2b3c4d5e6f70"
    )!
    nonisolated private static let officeID = UUID(
        uuidString: "0b7f3c1e-5a0e-4a53-9d43-3f3b6f0d2a11"
    )!

    nonisolated private static let profilePayload = Data(
        """
        {"data": {
            "id": "7878e808-a48f-4649-8a65-3feb6029a591",
            "display_name": "Alex Rivera"
        }}
        """.utf8
    )

    nonisolated private static let membershipsPayload = Data(
        #"{"data": ["dogpatch", "mission"]}"#.utf8
    )

    nonisolated private static func locationsPayload(
        defaultID: UUID, includeOffice: Bool = true
    ) -> Data {
        let home = """
            {
                "id": "\(homeID.uuidString.lowercased())",
                "label": "Home",
                "address": "Redwood City, CA",
                "latitude": 37.4852,
                "longitude": -122.2364,
                "is_default": \(defaultID == homeID),
                "kind": "home"
            }
            """
        let office = """
            {
                "id": "\(officeID.uuidString.lowercased())",
                "label": "Office",
                "address": null,
                "latitude": 37.7897,
                "longitude": -122.3942,
                "is_default": \(defaultID == officeID),
                "kind": "work"
            }
            """
        let items = includeOffice ? [home, office] : [home]
        return Data(#"{"data": [\#(items.joined(separator: ","))]}"#.utf8)
    }
}
