import MapKit
import SwiftUI

struct MapView: View {
    @State private var model: MapViewModel
    private let appModel: AppModel
    @State private var region: MKCoordinateRegion = .bayArea
    /// Bumped to move the map to `region`; see `GymMapView.regionChange`.
    @State private var regionChange = 0
    @State private var showsLabels = false
    /// The slider's live value. The model's hour, and the refetch, only follow it once a
    /// drag ends, so scrubbing across the day doesn't fire a request per step.
    @State private var sliderHour: Double
    @State private var isDraggingHour = false

    init(apiClient: APIClient, appModel: AppModel) {
        self.appModel = appModel
        _model = State(initialValue: MapViewModel(apiClient: apiClient, appModel: appModel))
        _sliderHour = State(initialValue: Double(appModel.selectedHour))
    }

    var body: some View {
        GymMapView(
            gyms: model.gyms,
            memberships: appModel.memberships,
            selectedGymID: model.selectedGymID,
            showsLabels: showsLabels,
            region: region,
            regionChange: regionChange,
            onSelect: { model.select($0) },
            onClearSelection: { model.clearSelection() },
            // The mockup shows pin labels from Leaflet zoom 11, which is roughly a 0.27°
            // longitude span at phone width.
            onSpanChange: { showsLabels = $0 <= 0.3 }
        )
        .ignoresSafeArea()
        .overlay(alignment: .center) { loadingIndicator }
        .overlay(alignment: .bottom) { selectedGymCard }
        .overlay(alignment: .top) {
            VStack(spacing: 10) {
                HStack {
                    MenuButton()
                    Spacer(minLength: 0)
                }
                hourSlider
                failureBanner
            }
            .padding(.horizontal, 16)
            .padding(.top, 62)
        }
        .task {
            await model.load()
            if let region = MapViewModel.region(fitting: model.gyms) {
                self.region = region
                regionChange += 1
            }
        }
        // A poll tick landed new busyness for the current hour.
        .onChange(of: appModel.liveRefreshCount) {
            Task { await model.load() }
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

    private var hourSlider: some View {
        HStack(spacing: 12) {
            Text(appModel.date(forHour: Int(sliderHour)), format: .dateTime.hour())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
            Slider(value: $sliderHour, in: 0...23, step: 1) { isEditing in
                isDraggingHour = isEditing
                if !isEditing { commitHour() }
            }
            .tint(Theme.brandPrimary)
            .accessibilityLabel("Time of day")
            .accessibilityValue(
                Text(appModel.date(forHour: Int(sliderHour)), format: .dateTime.hour())
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.14), radius: 24, y: 8)
        // VoiceOver adjustments change the value without a drag; commit those directly.
        .onChange(of: sliderHour) {
            if !isDraggingHour { commitHour() }
        }
    }

    private func commitHour() {
        let hour = Int(sliderHour)
        guard hour != appModel.selectedHour else { return }
        appModel.selectedHour = hour
        Task { await model.load() }
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
    let apiClient = APIClient(accessToken: { "preview-token" })
    MapView(apiClient: apiClient, appModel: AppModel(apiClient: apiClient))
}
