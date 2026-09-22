import MapKit
import SwiftUI

struct MapView: View {
    @State private var model: MapViewModel
    @State private var cameraPosition: MapCameraPosition = .region(.bayArea)
    @State private var showsLabels = false

    init(apiClient: APIClient) {
        _model = State(initialValue: MapViewModel(apiClient: apiClient))
    }

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(model.gyms) { gym in
                Annotation(gym.name, coordinate: gym.coordinate) {
                    GymPinView(
                        gym: gym,
                        isSelected: model.selectedGymID == gym.id,
                        showsLabel: showsLabels
                    )
                    .onTapGesture { model.select(gym) }
                }
                // The pin draws its own label; MapKit must not add a second one.
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .ignoresSafeArea()
        // The mockup shows pin labels from Leaflet zoom 11, which is roughly a 0.27°
        // longitude span at phone width.
        .onMapCameraChange(frequency: .continuous) { context in
            showsLabels = context.region.span.longitudeDelta <= 0.3
        }
        .onTapGesture { model.clearSelection() }
        .overlay(alignment: .center) { loadingIndicator }
        .overlay(alignment: .bottom) { selectedGymCard }
        .overlay(alignment: .top) { failureBanner }
        .task {
            await model.load()
            if let region = MapViewModel.region(fitting: model.gyms) {
                withAnimation { cameraPosition = .region(region) }
            }
        }
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if model.state == .loading, model.gyms.isEmpty {
            ProgressView()
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var selectedGymCard: some View {
        if let gym = model.selectedGym {
            SelectedGymCard(gym: gym) { model.clearSelection() }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.28), value: gym.id)
        }
    }

    @ViewBuilder
    private var failureBanner: some View {
        if let message = model.errorMessage {
            HStack(spacing: 12) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Button("Retry") { Task { await model.load() } }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.brandPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.14), radius: 24, y: 8)
            .padding(.horizontal, 16)
            .padding(.top, 62)
        }
    }
}

extension Gym {
    /// Kept in the map feature so `Core/Models/Gym.swift` stays free of MapKit.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension MKCoordinateRegion {
    /// Shown until the gyms load and the camera fits them.
    static let bayArea = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.6, longitude: -122.2),
        span: MKCoordinateSpan(latitudeDelta: 0.9, longitudeDelta: 0.9)
    )
}

#Preview {
    MapView(apiClient: APIClient(accessToken: { "preview-token" }))
}
