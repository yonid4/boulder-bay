import MapKit

extension MKMapItem {
    /// Opens Apple Maps on the gym, built from its coordinates rather than a geocoded
    /// address — the coordinates are the verified value. `address` is display text only.
    @MainActor
    static func openInAppleMaps(name: String, latitude: Double, longitude: Double) {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
