import MapKit
import SnapshotTesting
import SwiftUI
import Testing

@testable import BoulderBay

@MainActor
@Suite
struct LocationSwitcherTests {
    private func place(_ label: String, kind: LocationKind) -> SavedLocation {
        SavedLocation(
            id: UUID(), label: label, address: nil, latitude: 37.8, longitude: -122.27,
            isDefault: false, kind: kind
        )
    }

    private func makeMapModel() -> MapViewModel {
        let apiClient = APIClient(accessToken: { "token" })
        return MapViewModel(apiClient: apiClient, appModel: AppModel(apiClient: apiClient))
    }

    // MARK: Flying to a place

    @Test func flyingCentersOnThePlaceCloseEnoughForPinLabels() {
        let region = makeMapModel().flyTo(place("Home", kind: .home))
        #expect(region.center.latitude == 37.8)
        #expect(region.center.longitude == -122.27)
        #expect(region.span.longitudeDelta <= 0.3)
    }

    @Test func flyingDropsTheSelectedGym() throws {
        let model = makeMapModel()
        let gym = try #require(Self.gym)
        model.select(gym)

        _ = model.flyTo(place("Home", kind: .home))

        #expect(model.selectedGymID == nil)
    }

    /// Otherwise gyms arriving just after the pick would pull the camera back out.
    @Test func flyingStopsALaterFirstFit() {
        let model = makeMapModel()
        let region = model.flyTo(place("Home", kind: .home))

        #expect(model.regionForFirstFit() == nil)
        #expect(model.cameraRegion?.center.latitude == region.center.latitude)
    }

    private static var gym: Gym? {
        try? APIClient.jsonDecoder.decode(
            APIEnvelope<[Gym]>.self, from: GymDecodingTests.payload
        ).data.first
    }

    // MARK: The chip

    @Test func chipForEachKind() {
        let chips = VStack(alignment: .leading, spacing: 12) {
            LocationChip(location: place("Home", kind: .home))
            LocationChip(location: place("Work", kind: .work))
            LocationChip(location: place("Climbing buddy", kind: .other))
        }
        assertSnapshot(
            of: chips.frame(width: 280, alignment: .leading).padding(16)
                .background(Theme.background),
            as: .image(perceptualPrecision: 0.98, layout: .sizeThatFits)
        )
    }

    /// The row beside the menu button is narrow, so a long label truncates to one line.
    @Test func chipWithALongLabelTruncates() {
        let chip = LocationChip(
            location: place("The climbing buddy's place across the whole bay", kind: .other)
        )
        assertSnapshot(
            of: chip.frame(width: 280, alignment: .leading).padding(16)
                .background(Theme.background),
            as: .image(perceptualPrecision: 0.98, layout: .sizeThatFits)
        )
    }
}
