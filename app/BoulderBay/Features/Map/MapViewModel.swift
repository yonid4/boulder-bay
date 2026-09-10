import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

/// One pin as the map draws it: the gym, its busyness at the selected hour, and the
/// flags that change how it renders.
struct MapPin: Identifiable, Hashable {
    let gym: Gym
    let busyPct: Int?
    let isOpen: Bool
    let isMember: Bool
    let travelMinutes: Int?
    let score: Double

    var id: String { gym.slug }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: gym.latitude, longitude: gym.longitude)
    }
    var level: BusynessLevel? { busyPct.map(BusynessLevel.init(percent:)) }
}

/// Composes the gym, ranking, membership and location stores into what the map shows.
/// Owns the camera, the selection, the time-chip state, and the overlap rule: zoomed
/// out, pins that would overlap collapse to the highest-priority gym — members first,
/// then score — with no cluster counts.
@MainActor
@Observable
final class MapViewModel {
    /// Below this latitude span each pin grows its busyness chip (the mockup's zoom ≥ 11).
    static let chipSpan: CLLocationDegrees = 0.25
    /// Minimum on-screen distance between pins, in points, with and without chips.
    static let minimumSpacing: (chips: CGFloat, dots: CGFloat) = (66, 34)
    /// How the map opens: the saved location with the whole Bay in view.
    static let initialSpan = MKCoordinateSpan(latitudeDelta: 0.55, longitudeDelta: 0.55)

    private(set) var selectedSlug: String?
    var isTimeOpen = false
    var camera: MapCameraPosition = .automatic
    private(set) var visibleRegion: MKCoordinateRegion?
    var viewSize: CGSize = CGSize(width: 402, height: 874)

    private let gyms: GymStore
    private let rankings: RankingStore
    private let memberships: MembershipStore
    private let locations: LocationStore

    init(gyms: GymStore, rankings: RankingStore, memberships: MembershipStore, locations: LocationStore) {
        self.gyms = gyms
        self.rankings = rankings
        self.memberships = memberships
        self.locations = locations
        if let location = locations.current {
            camera = .region(MKCoordinateRegion(center: location.coordinate, span: Self.initialSpan))
        }
    }

    // MARK: Derived state

    var location: SavedLocation? { locations.current }
    var showChips: Bool { (visibleRegion?.span.latitudeDelta ?? Self.initialSpan.latitudeDelta) < Self.chipSpan }

    /// Every gym with its ranking joined in, before the overlap rule.
    var allPins: [MapPin] {
        gyms.gyms.map { gym in
            let entry = rankings.entry(for: gym.slug)
            return MapPin(
                gym: gym,
                busyPct: entry?.busyPct ?? (rankings.isPlanning ? nil : gym.live?.busyPct),
                isOpen: entry?.isOpen ?? (gym.hoursToday?.contains(ClockTime(hour: rankings.effectiveHour)) ?? false),
                isMember: memberships.isMember(gym.slug),
                travelMinutes: entry?.travelMinutes,
                score: entry?.score ?? -.infinity
            )
        }
    }

    /// The pins actually drawn: overlapping ones collapse to the highest priority. The
    /// selected pin is always kept.
    var visiblePins: [MapPin] {
        Self.thin(
            allPins, region: visibleRegion, size: viewSize,
            spacing: showChips ? Self.minimumSpacing.chips : Self.minimumSpacing.dots,
            keep: selectedSlug
        )
    }

    var selectedPin: MapPin? {
        selectedSlug.flatMap { slug in allPins.first { $0.gym.slug == slug } }
    }

    var bestPin: MapPin? {
        rankings.best.flatMap { best in allPins.first { $0.gym.slug == best.slug } }
    }

    var bestLabel: String {
        rankings.isPlanning ? "Best at \(Format.hour(rankings.effectiveHour))" : "Best right now"
    }

    var timeChipLabel: String {
        rankings.isPlanning ? Format.hour(rankings.effectiveHour) : "Now"
    }

    var plannableHours: ClosedRange<Int>? { rankings.plannableHours }

    var isLoading: Bool { gyms.state == .loading && gyms.gyms.isEmpty }

    // MARK: Actions

    func load() async {
        await gyms.loadIfNeeded()
        await memberships.loadIfNeeded()
        await rankings.refreshIfNeeded()
    }

    func select(_ slug: String?) {
        selectedSlug = slug
    }

    func cameraChanged(region: MKCoordinateRegion) {
        visibleRegion = region
    }

    /// Selects the top-ranked gym and flies to it, zooming in if the map is zoomed out.
    func pickBest() {
        guard let best = bestPin else { return }
        selectedSlug = best.gym.slug
        let currentSpan = visibleRegion?.span.latitudeDelta ?? Self.initialSpan.latitudeDelta
        let span = min(currentSpan, 0.08)
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .region(
                MKCoordinateRegion(
                    center: best.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                )
            )
        }
    }

    func toggleTime() {
        isTimeOpen.toggle()
    }

    func closeTime() {
        isTimeOpen = false
    }

    /// Bound to the scrubber. Changing it drops the selection; the store debounces the
    /// refetch.
    var plannedHour: Int? {
        get { rankings.plannedHour }
        set {
            guard newValue != rankings.plannedHour else { return }
            rankings.plan(hour: newValue)
            selectedSlug = nil
        }
    }

    // MARK: Overlap rule

    /// Drops any pin that would sit within `spacing` points of a higher-priority pin
    /// already placed. Priority is member first, then score. `keep` is never dropped.
    static func thin(_ pins: [MapPin], region: MKCoordinateRegion?, size: CGSize, spacing: CGFloat, keep: String?) -> [MapPin] {
        guard let region, size.width > 0, size.height > 0 else { return pins }
        let ordered = pins.sorted { lhs, rhs in
            if (lhs.gym.slug == keep) != (rhs.gym.slug == keep) { return lhs.gym.slug == keep }
            if lhs.isMember != rhs.isMember { return lhs.isMember }
            return lhs.score > rhs.score
        }
        var placed: [CGPoint] = []
        var result: [MapPin] = []
        for pin in ordered {
            let point = project(pin.coordinate, in: region, size: size)
            let collides = placed.contains { hypot($0.x - point.x, $0.y - point.y) < spacing }
            if collides, pin.gym.slug != keep { continue }
            placed.append(point)
            result.append(pin)
        }
        return result
    }

    /// Equirectangular projection into view points — close enough at Bay Area scale.
    static func project(_ coordinate: CLLocationCoordinate2D, in region: MKCoordinateRegion, size: CGSize) -> CGPoint {
        let x = (coordinate.longitude - (region.center.longitude - region.span.longitudeDelta / 2))
            / region.span.longitudeDelta * size.width
        let y = ((region.center.latitude + region.span.latitudeDelta / 2) - coordinate.latitude)
            / region.span.latitudeDelta * size.height
        return CGPoint(x: x, y: y)
    }
}

extension SavedLocation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
