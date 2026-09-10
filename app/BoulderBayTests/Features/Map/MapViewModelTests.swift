import CoreLocation
import Foundation
import MapKit
import Testing

@testable import BoulderBay

@MainActor
struct MapViewModelTests {
    private func makeModel() async -> (AppContainer, MapViewModel) {
        let container = AppContainer(
            auth: MockAuthService.signedIn(as: .preview),
            api: MockAPIClient(now: { wednesday5pm }),
            now: { wednesday5pm }
        )
        await container.gyms.load()
        await container.locations.load()
        await container.memberships.load()
        let model = MapViewModel(
            gyms: container.gyms, rankings: container.rankings,
            memberships: container.memberships, locations: container.locations
        )
        await model.load()
        return (container, model)
    }

    @Test func loadsSixteenPinsJoinedWithRankings() async {
        let (_, model) = await makeModel()

        #expect(model.allPins.count == 16)
        let belmont = model.allPins.first { $0.id == "mv-belmont" }
        #expect(belmont?.isMember == true)
        #expect(belmont?.travelMinutes != nil)
        #expect(belmont?.busyPct != nil)
        #expect(model.location?.label == "Home")
        #expect(model.bestPin != nil)
        #expect(model.bestLabel == "Best right now")
        #expect(model.timeChipLabel == "Now")
    }

    @Test func chipsAppearOnlyWhenZoomedIn() async {
        let (_, model) = await makeModel()
        #expect(!model.showChips)

        model.cameraChanged(region: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.41),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        ))
        #expect(model.showChips)
    }

    @Test func overlappingPinsCollapseToMemberThenScore() {
        func pin(_ slug: String, lat: Double, member: Bool, score: Double) -> MapPin {
            let gym = Gym(
                slug: slug, name: slug, brand: .independent, city: "", address: nil,
                latitude: lat, longitude: -122.4, logoURL: nil, websiteURL: nil, waiverURL: nil,
                rates: GymRates(dayPassCents: nil, dayPassPeakCents: nil, peakStartsAt: nil, monthlyCents: nil),
                hoursToday: nil, live: nil
            )
            return MapPin(gym: gym, busyPct: 50, isOpen: true, isMember: member, travelMinutes: 10, score: score)
        }
        // Three gyms within a few points of each other, one far away.
        let pins = [
            pin("high", lat: 37.7800, member: false, score: 90),
            pin("member", lat: 37.7801, member: true, score: 40),
            pin("low", lat: 37.7802, member: false, score: 10),
            pin("far", lat: 37.9000, member: false, score: 5),
        ]
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.8, longitude: -122.4),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        let size = CGSize(width: 400, height: 800)

        let thinned = MapViewModel.thin(pins, region: region, size: size, spacing: 34, keep: nil)
        #expect(thinned.map(\.id) == ["member", "far"])

        // The selected pin takes the slot, even over a member.
        let kept = MapViewModel.thin(pins, region: region, size: size, spacing: 34, keep: "low")
        #expect(kept.map(\.id) == ["low", "far"])

        // Zoomed way in, nothing collides.
        let zoomed = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7801, longitude: -122.4),
            span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
        )
        #expect(MapViewModel.thin(pins, region: zoomed, size: size, spacing: 34, keep: nil).count == 4)
    }

    @Test func pickBestSelectsTheTopRankedGymAndZoomsIn() async {
        let (container, model) = await makeModel()

        model.pickBest()

        #expect(model.selectedSlug == container.rankings.best?.slug)
        #expect(model.selectedPin?.id == container.rankings.best?.slug)
        #expect(model.camera.region?.span.latitudeDelta ?? 1 <= 0.08)
    }

    @Test func changingTheHourDropsTheSelectionAndRefetches() async {
        let (container, model) = await makeModel()
        model.select("mission")
        #expect(model.selectedPin?.id == "mission")

        model.plannedHour = 20
        #expect(model.selectedSlug == nil)
        #expect(container.rankings.isPlanning)
        #expect(model.bestLabel == "Best at 8 PM")
        #expect(model.timeChipLabel == "8 PM")

        await waitUntil(timeout: .seconds(3)) { container.rankings.rankings.map { BayArea.hour($0.at) == 20 } ?? false }
        #expect(model.allPins.allSatisfy { $0.busyPct == nil || $0.isOpen })
    }

    @Test func tapToDeselect() async {
        let (_, model) = await makeModel()
        model.select("mosaic")
        model.select(nil)
        #expect(model.selectedPin == nil)
    }
}
