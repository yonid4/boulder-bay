import Foundation
import MapKit

/// Drives the map screen: the gym list, which pin is selected, the hour of today the gyms
/// are resolved for, and the camera region that frames them.
@MainActor
@Observable
final class MapViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var gyms: [Gym] = []
    private(set) var state: LoadState = .idle
    private(set) var selectedGymID: Gym.ID?
    /// The hour of today (0–23) the gyms are resolved for. Defaults to the current hour
    /// with the minutes dropped, so 5:59 PM starts at 17.
    var selectedHour: Int

    private let apiClient: APIClient
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    /// The hour an in-flight load is fetching, so a repeat of the same load is skipped.
    private var loadingHour: Int?

    init(
        apiClient: APIClient,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.apiClient = apiClient
        self.calendar = calendar
        self.now = now
        selectedHour = calendar.component(.hour, from: now())
    }

    var selectedGym: Gym? {
        gyms.first { $0.id == selectedGymID }
    }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// Today at `hour`:00 in the device's timezone.
    func date(forHour hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now()) ?? now()
    }

    func load() async {
        let hour = selectedHour
        guard loadingHour != hour else { return }
        loadingHour = hour
        state = .loading

        do {
            let gyms = try await apiClient.gyms(at: date(forHour: hour))
            // The hour moved while this was in flight; the newer load owns the result.
            guard hour == selectedHour else { return }
            self.gyms = gyms
            // A gym can disappear between loads (deactivated); don't keep a dangling selection.
            if selectedGym == nil { selectedGymID = nil }
            state = .loaded
        } catch {
            guard hour == selectedHour else { return }
            state = .failed(Self.message(for: error))
        }
        loadingHour = nil
    }

    func select(_ gym: Gym) {
        selectedGymID = gym.id
    }

    func clearSelection() {
        selectedGymID = nil
    }

    /// "Open" / "Closed" for a pin label. Busyness has no percentage or level yet — the
    /// backend returns those as null until the scraper lands — so open state is the only
    /// thing a pin can say about a gym right now.
    static func openStateLabel(for gym: Gym) -> String {
        gym.busyness.isOpen ? "Open" : "Closed"
    }

    /// A region framing every gym, or `nil` for an empty list so the caller keeps its default.
    static func region(fitting gyms: [Gym]) -> MKCoordinateRegion? {
        guard let first = gyms.first else { return nil }

        var minLatitude = first.latitude, maxLatitude = first.latitude
        var minLongitude = first.longitude, maxLongitude = first.longitude
        for gym in gyms.dropFirst() {
            minLatitude = min(minLatitude, gym.latitude)
            maxLatitude = max(maxLatitude, gym.latitude)
            minLongitude = min(minLongitude, gym.longitude)
            maxLongitude = max(maxLongitude, gym.longitude)
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                // Padded so pins aren't flush against the edges, and floored so a single
                // gym frames its neighbourhood rather than its doorstep.
                latitudeDelta: max((maxLatitude - minLatitude) * Self.regionPadding, Self.minimumSpan),
                longitudeDelta: max(
                    (maxLongitude - minLongitude) * Self.regionPadding, Self.minimumSpan
                )
            )
        )
    }

    private static let regionPadding = 1.35
    private static let minimumSpan = 0.02

    private static func message(for error: Error) -> String {
        switch error {
        case APIError.badStatus(401):
            "Your session has expired. Sign in again."
        case APIError.badStatus(let code):
            "The server returned an error (\(code))."
        case APIError.decoding:
            "The server sent something unexpected."
        default:
            "Couldn't reach the server. Check your connection."
        }
    }
}
