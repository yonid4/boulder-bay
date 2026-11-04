import MapKit
import SwiftUI
import Testing
import UIKit

@testable import BoulderBay

/// A map rebuilt on returning to the Map screen has to open at the zoom it was given. MapKit
/// isn't handed a size until after `makeUIView`, so this runs the real view in a window.
@MainActor
struct GymMapViewTests {
    @Test func aNewMapOpensOnTheRegionItWasGiven() async throws {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.8716, longitude: -122.2727),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = UIHostingController(
            rootView: GymMapView(
                gyms: [],
                memberships: [],
                selectedGymID: nil,
                showsLabels: true,
                region: region,
                regionChange: 0,
                onSelect: { _ in },
                onClearSelection: {},
                onSpanChange: { _ in },
                onRegionChange: { _ in }
            )
        )
        window.windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        window.isHidden = false
        defer { window.isHidden = true }

        // SwiftUI builds the map on a later pass, and `makeUIView` reapplies the region after that.
        var found: MKMapView?
        for _ in 0..<60 where found == nil {
            window.layoutIfNeeded()
            found = Self.mapView(in: window)
            try await Task.sleep(for: .milliseconds(50))
        }
        let mapView = try #require(found)
        try await Task.sleep(for: .milliseconds(300))

        #expect(mapView.bounds.width > 0)
        #expect(abs(mapView.region.center.latitude - 37.8716) < 0.01)
        #expect(abs(mapView.region.center.longitude - -122.2727) < 0.01)
        // MapKit widens one axis to fit the screen's shape, so this isn't exact, but it's the
        // same neighbourhood rather than the whole Bay.
        #expect(mapView.region.span.longitudeDelta < 0.1)
    }

    private static func mapView(in view: UIView) -> MKMapView? {
        if let mapView = view as? MKMapView { return mapView }
        return view.subviews.lazy.compactMap { mapView(in: $0) }.first
    }
}
