import MapKit
import SwiftUI

/// The map under `MapView`: an `MKMapView` with one `GymPinView` per gym.
///
/// UIKit rather than SwiftUI's `Map`, for one reason: `Map` can't say which annotation draws
/// on top. It put pins lower on the screen in front, so a member gym, or even the selected
/// one, hid under any gym just south of it. `MKAnnotationView.zPriority` can
/// (`MapViewModel.zPriority`).
struct GymMapView: UIViewRepresentable {
    let gyms: [Gym]
    let memberships: Set<String>
    let selectedGymID: Gym.ID?
    let showsLabels: Bool
    /// The region to show. The map moves only when `regionChange` changes, so panning
    /// around isn't undone by the next update.
    let region: MKCoordinateRegion
    let regionChange: Int
    let onSelect: (Gym) -> Void
    let onClearSelection: () -> Void
    /// The visible longitude span, reported as the camera moves.
    let onSpanChange: (CLLocationDegrees) -> Void
    /// Where the camera came to rest after moving.
    let onRegionChange: (MKCoordinateRegion) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.register(
            GymAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: GymAnnotationView.reuseIdentifier
        )
        mapView.setRegion(region, animated: false)
        context.coordinator.appliedRegionChange = regionChange
        // The map has no size yet, so MapKit can't honor the zoom exactly. Apply it again once
        // laid out, unless a newer move has taken over: this is where a returning map's zoom
        // comes from.
        let (region, change) = (region, regionChange)
        DispatchQueue.main.async { [weak mapView, weak coordinator = context.coordinator] in
            guard coordinator?.appliedRegionChange == change else { return }
            mapView?.setRegion(region, animated: false)
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if coordinator.appliedRegionChange != regionChange {
            coordinator.appliedRegionChange = regionChange
            mapView.setRegion(region, animated: true)
        }

        coordinator.syncAnnotations(on: mapView)
        coordinator.syncSelection(on: mapView)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: GymMapView
        var appliedRegionChange: Int?
        /// One annotation per gym, kept across updates so a poll tick restyles pins in place
        /// rather than removing and re-adding them.
        private var annotations: [Gym.ID: GymAnnotation] = [:]
        /// Set while the map's selection is changed to match `selectedGymID`, so the delegate
        /// calls that causes aren't reported back as taps.
        private var isSyncingSelection = false

        init(_ parent: GymMapView) {
            self.parent = parent
        }

        func syncAnnotations(on mapView: MKMapView) {
            let gymsByID = Dictionary(parent.gyms.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            let gone = annotations.filter { gymsByID[$0.key] == nil }
            mapView.removeAnnotations(Array(gone.values))
            gone.keys.forEach { annotations[$0] = nil }

            var added: [GymAnnotation] = []
            for gym in parent.gyms {
                if let annotation = annotations[gym.id] {
                    annotation.gym = gym
                    if let view = mapView.view(for: annotation) as? GymAnnotationView {
                        configure(view, for: gym)
                    }
                } else {
                    let annotation = GymAnnotation(gym: gym)
                    annotations[gym.id] = annotation
                    added.append(annotation)
                }
            }
            mapView.addAnnotations(added)
        }

        func syncSelection(on mapView: MKMapView) {
            isSyncingSelection = true
            defer { isSyncingSelection = false }

            let wanted = parent.selectedGymID.flatMap { annotations[$0] }
            for case let annotation as GymAnnotation in mapView.selectedAnnotations
            where annotation !== wanted {
                mapView.deselectAnnotation(annotation, animated: false)
            }
            if let wanted, !mapView.selectedAnnotations.contains(where: { $0 === wanted }) {
                mapView.selectAnnotation(wanted, animated: false)
            }
        }

        private func configure(_ view: GymAnnotationView, for gym: Gym) {
            let isMember = parent.memberships.contains(gym.slug)
            view.show(
                GymPinView(
                    gym: gym,
                    isSelected: parent.selectedGymID == gym.id,
                    showsLabel: parent.showsLabels,
                    isMember: isMember
                ),
                accessibilityLabel: isMember ? "\(gym.name), member" : gym.name
            )
            // Set both: MapKit swaps in `selectedZPriority` for a pin it has selected.
            let priority = MapViewModel.zPriority(
                isSelected: parent.selectedGymID == gym.id, isMember: isMember
            )
            view.zPriority = priority
            view.selectedZPriority = priority
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? GymAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: GymAnnotationView.reuseIdentifier, for: annotation
            )
            if let view = view as? GymAnnotationView {
                configure(view, for: annotation.gym)
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            guard !isSyncingSelection, let annotation = annotation as? GymAnnotation else { return }
            parent.onSelect(annotation.gym)
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: any MKAnnotation) {
            guard !isSyncingSelection else { return }
            // Moving from one pin to another deselects the first before selecting the second;
            // only a tap on the bare map leaves nothing selected once the touch settles.
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView, mapView.selectedAnnotations.isEmpty else { return }
                self.parent.onClearSelection()
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            parent.onSpanChange(mapView.region.span.longitudeDelta)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.region)
        }
    }
}

/// One gym on the map. A class, as `MKAnnotation` requires; the gym is replaced on each load.
final class GymAnnotation: NSObject, MKAnnotation {
    var gym: Gym

    init(gym: Gym) {
        self.gym = gym
    }

    // Gyms don't move, so the coordinate needs no KVO.
    var coordinate: CLLocationCoordinate2D { gym.coordinate }
}

/// Hosts a `GymPinView`, sized to fit it, with the dot's center on the gym's coordinate.
final class GymAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "GymPin"

    private var host: UIHostingController<GymPinView>?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(_ pin: GymPinView, accessibilityLabel: String) {
        if let host {
            host.rootView = pin
        } else {
            let host = UIHostingController(rootView: pin)
            host.view.backgroundColor = .clear
            // Taps go to the annotation view, so MapKit's own selection handles them.
            host.view.isUserInteractionEnabled = false
            addSubview(host.view)
            self.host = host
        }
        self.accessibilityLabel = accessibilityLabel

        guard let host else { return }
        let pinSize = host.sizeThatFits(in: UIView.layoutFittingExpandedSize)
        layOut(host.view, pinSize: pinSize, showsLabel: pin.showsLabel)
    }

    /// MapKit picks the pin for a tap from this view's frame, so the frame has to cover only
    /// what's visible: the whole pin with its label, or a tap target around the dot without
    /// one, with the hidden label hanging outside it. The pin itself never changes size, and
    /// the dot stays on the same spot on screen through the switch.
    private func layOut(_ pinView: UIView, pinSize: CGSize, showsLabel: Bool) {
        let dotInPin = CGPoint(x: pinSize.width / 2, y: pinSize.height - Self.dotRadius)
        let dotOnScreen = superview.map { _ in
            CGPoint(x: frame.minX + currentDot.x, y: frame.minY + currentDot.y)
        }

        UIView.performWithoutAnimation {
            let size = showsLabel ? pinSize : CGSize(width: Self.dotTapSize, height: Self.dotTapSize)
            let dot = showsLabel ? dotInPin : CGPoint(x: size.width / 2, y: size.height / 2)
            bounds = CGRect(origin: .zero, size: size)
            pinView.frame = CGRect(
                origin: CGPoint(x: dot.x - dotInPin.x, y: dot.y - dotInPin.y), size: pinSize
            )
            // The view is centered on the coordinate by default; move it so the dot's center
            // lands there instead.
            centerOffset = CGPoint(x: size.width / 2 - dot.x, y: size.height / 2 - dot.y)
            currentDot = dot
            // MapKit may only apply the new offset on its next pass; don't wait for it.
            if let dotOnScreen {
                center = CGPoint(
                    x: dotOnScreen.x + size.width / 2 - dot.x,
                    y: dotOnScreen.y + size.height / 2 - dot.y
                )
            }
        }
    }

    /// Where the dot's center is in this view, for keeping it in place when the frame changes.
    private var currentDot: CGPoint = .zero

    private static let dotRadius: CGFloat = 7
    private static let dotTapSize: CGFloat = 28
}
