import Foundation
import MapKit

/// Drives the map screen: which pin is selected, and the camera region that frames the gyms.
/// The gym list and the hour it is resolved for live on `AppModel`, shared with other screens.
@MainActor
@Observable
final class MapViewModel {
    private(set) var selectedGymID: Gym.ID?

    let appModel: AppModel
    /// Unused since the gym list moved to `AppModel`. Kept for the map's rankings call (A14),
    /// so `MapView`'s initialiser needn't change twice.
    private let apiClient: APIClient

    init(apiClient: APIClient, appModel: AppModel) {
        self.apiClient = apiClient
        self.appModel = appModel
    }

    var gyms: [Gym] {
        appModel.gyms
    }

    var state: AppModel.LoadState {
        appModel.gymsState
    }

    var selectedGym: Gym? {
        gyms.first { $0.id == selectedGymID }
    }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    func load() async {
        await appModel.loadGyms()
        // A gym can disappear between loads (deactivated); don't keep a dangling selection.
        if selectedGym == nil { selectedGymID = nil }
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

    /// Where a pin sits among overlapping pins: the selected gym on top, then member gyms, then
    /// the rest — the mockup's `zIndexOffset` (selected 1000, member 500, others 0). SwiftUI's
    /// `Map` has no such setting; it put pins lower on the screen in front whatever their list
    /// order, which is why the map is an `MKMapView`.
    static func zPriority(isSelected: Bool, isMember: Bool) -> MKAnnotationViewZPriority {
        if isSelected { return .max }
        return isMember ? memberZPriority : .defaultUnselected
    }

    /// Between `.defaultUnselected` (500) and `.max` (1000).
    static let memberZPriority = MKAnnotationViewZPriority(rawValue: 750)

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
