import Foundation
import MapKit

/// Drives the map screen: the gym list, which pin is selected, and the camera region that
/// frames them. The hour the gyms are resolved for lives on `AppModel`, shared with Rankings.
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

    let appModel: AppModel
    private let apiClient: APIClient
    /// The hour an in-flight load is fetching, so a repeat of the same load is skipped.
    private var loadingHour: Int?

    init(apiClient: APIClient, appModel: AppModel) {
        self.apiClient = apiClient
        self.appModel = appModel
    }

    var selectedGym: Gym? {
        gyms.first { $0.id == selectedGymID }
    }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    func load() async {
        let hour = appModel.selectedHour
        guard loadingHour != hour else { return }
        loadingHour = hour
        state = .loading

        do {
            let gyms = try await apiClient.gyms(at: appModel.date(forHour: hour))
            // The hour moved while this was in flight; the newer load owns the result.
            guard hour == appModel.selectedHour else { return }
            self.gyms = gyms
            // A gym can disappear between loads (deactivated); don't keep a dangling selection.
            if selectedGym == nil { selectedGymID = nil }
            state = .loaded
        } catch {
            guard hour == appModel.selectedHour else { return }
            state = .failed(APIError.message(for: error))
        }
        loadingHour = nil
    }

    func select(_ gym: Gym) {
        selectedGymID = gym.id
    }

    func clearSelection() {
        selectedGymID = nil
    }

    /// The busyness line for a pin label or card: "Quiet · 32%", plus "· Live" only when the
    /// reading is live for the current hour — not one observed in a past hour, nor a forecast.
    /// Leads with the word, not the number. Without a reading it falls back to "Open" /
    /// "Closed" — an open gym with no forecast is never shown as 0%.
    static func busynessLabel(for gym: Gym) -> String {
        let busyness = gym.busyness
        guard busyness.isOpen else { return "Closed" }
        guard let level = busyness.level, let percent = busyness.busyPct else { return "Open" }
        let label = "\(level.rawValue.capitalized) · \(percent)%"
        return busyness.source == .live ? "\(label) · Live" : label
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
}
