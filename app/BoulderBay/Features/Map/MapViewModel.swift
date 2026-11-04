import Foundation
import MapKit

/// Drives the map screen: which pin is selected, and the camera. Owned by `AppShell`, so both
/// outlast `MapView`, which is rebuilt each time the route changes. The gym list and the hour it
/// is resolved for live on `AppModel`, shared with other screens.
@MainActor
@Observable
final class MapViewModel {
    private(set) var selectedGymID: Gym.ID?
    /// Whether the best-pick button is waiting on the rankings.
    private(set) var isFindingBestPick = false
    /// Why the best-pick button couldn't fly anywhere: nothing is open, or the request failed.
    private(set) var bestPickMessage: String?
    /// Where the camera last came to rest, for a rebuilt `MapView` to open on. Nil until the
    /// camera has first fit the gyms. It changes with every pan, which nothing redraws for.
    @ObservationIgnored private(set) var cameraRegion: MKCoordinateRegion?

    let appModel: AppModel

    init(appModel: AppModel) {
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

    /// For the map appearing: keeps a list already loaded for the selected hour.
    func loadIfNeeded() async {
        guard !appModel.hasGymsForSelectedHour else { return }
        await load()
    }

    /// The region for the camera's first fit: the first time there are gyms to frame, however
    /// long that took (a retry, a load the slider replaced), and only once.
    func regionForFirstFit() -> MKCoordinateRegion? {
        guard cameraRegion == nil, let region = Self.region(fitting: gyms) else { return nil }
        cameraRegion = region
        return region
    }

    /// Records where the camera came to rest. Before the first fit it is only on its default,
    /// which isn't worth returning to.
    func cameraMoved(to region: MKCoordinateRegion) {
        guard cameraRegion != nil else { return }
        cameraRegion = region
    }

    /// The region to fly to when `location` is chosen, close enough for the pin labels to show.
    /// As in the mockup, it also drops the selected gym. Recording the camera here stops a first
    /// fit that hasn't happened yet from pulling it away again.
    func flyTo(_ location: SavedLocation) -> MKCoordinateRegion {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: location.latitude, longitude: location.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: Self.placeSpan, longitudeDelta: Self.placeSpan)
        )
        cameraRegion = region
        clearSelection()
        return region
    }

    private static let placeSpan: CLLocationDegrees = 0.12

    /// Selects rank 1 for the selected place and hour, returning the region to fly to, or nil when
    /// there's nowhere to go: `bestPickMessage` says why, unless the user moved to another place
    /// or hour while this waited, which makes the answer out of date.
    func findBestPick() async -> MKCoordinateRegion? {
        guard !isFindingBestPick else { return nil }
        let hour = appModel.selectedHour
        isFindingBestPick = true
        bestPickMessage = nil
        defer { isFindingBestPick = false }

        do {
            let rankings = try await appModel.rankingsForSelection(limit: 1)
            guard
                hour == appModel.selectedHour,
                rankings.location.id == appModel.selectedLocationID
            else { return nil }

            guard let best = rankings.rankedGyms.first?.gym else {
                bestPickMessage = RankingsFormat.nothingOpen(
                    near: rankings.location.label, hour: hour, isNow: appModel.isSelectedHourNow
                )
                return nil
            }
            select(best)
            return region(flyingTo: best)
        } catch {
            guard hour == appModel.selectedHour else { return nil }
            bestPickMessage = APIError.message(for: error)
            return nil
        }
    }

    func dismissBestPickMessage() {
        bestPickMessage = nil
    }

    /// Centres `gym`, zooming in to at least `placeSpan` as a place does, but never out: the
    /// mockup's `max(zoom, 12)`.
    private func region(flyingTo gym: Gym) -> MKCoordinateRegion {
        let span = min(cameraRegion?.span.longitudeDelta ?? Self.placeSpan, Self.placeSpan)
        let region = MKCoordinateRegion(
            center: gym.coordinate,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
        cameraRegion = region
        return region
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
