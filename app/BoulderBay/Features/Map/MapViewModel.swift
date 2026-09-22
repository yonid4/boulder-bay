import Foundation
import MapKit

/// Drives the map screen: the gym list, which pin is selected, and the camera region
/// that frames them.
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

    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    var selectedGym: Gym? {
        gyms.first { $0.id == selectedGymID }
    }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading

        do {
            gyms = try await apiClient.gyms()
            // A gym can disappear between loads (deactivated); don't keep a dangling selection.
            if selectedGym == nil { selectedGymID = nil }
            state = .loaded
        } catch {
            state = .failed(Self.message(for: error))
        }
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
