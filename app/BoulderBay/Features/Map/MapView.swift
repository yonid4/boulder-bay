import MapKit
import SwiftUI

struct MapView: View {
    private let model: MapViewModel
    private let appModel: AppModel
    @State private var region: MKCoordinateRegion
    /// Bumped to move the map to `region`; see `GymMapView.regionChange`.
    @State private var regionChange = 0
    @State private var showsLabels: Bool
    /// The slider's live value. The model's hour, and the refetch, only follow it once a
    /// drag ends, so scrubbing across the day doesn't fire a request per step.
    @State private var sliderHour: Double
    @State private var isDraggingHour = false
    private let onOpenGym: (Gym) -> Void

    /// The mockup shows pin labels from Leaflet zoom 11, which is roughly a 0.27° longitude
    /// span at phone width.
    private static let maximumLabelSpan: CLLocationDegrees = 0.3

    init(model: MapViewModel, onOpenGym: @escaping (Gym) -> Void = { _ in }) {
        self.model = model
        appModel = model.appModel
        self.onOpenGym = onOpenGym
        let region = model.cameraRegion
        _region = State(initialValue: region ?? .bayArea)
        _showsLabels = State(
            initialValue: region.map { $0.span.longitudeDelta <= Self.maximumLabelSpan } ?? false
        )
        _sliderHour = State(initialValue: Double(model.appModel.selectedHour))
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
            onSpanChange: { showsLabels = $0 <= Self.maximumLabelSpan },
            onRegionChange: { model.cameraMoved(to: $0) }
        )
        .ignoresSafeArea()
        .overlay(alignment: .center) { loadingIndicator }
        .overlay(alignment: .bottom) { selectedGymCard }
        .overlay(alignment: .top) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    MenuButton()
                    LocationSwitcher(
                        locations: appModel.locationsInDisplayOrder,
                        selected: appModel.selectedLocation,
                        onSelect: { appModel.selectLocation(id: $0.id) }
                    )
                    Spacer(minLength: 0)
                }
                hourSlider
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    BestPickButton(
                        title: RankingsFormat.bestButton(
                            hour: appModel.selectedHour, isNow: appModel.isSelectedHourNow
                        ),
                        isLoading: model.isFindingBestPick,
                        action: showBestPick
                    )
                }
                bestPickBanner
                failureBanner
            }
            .padding(.horizontal, 16)
            .padding(.top, 62)
        }
        // Starts again each time this screen appears, including back from gym detail; a list
        // already loaded for this hour stays. `AppModel` refreshes it on poll pings.
        .task { await model.loadIfNeeded() }
        // The hour moved without the slider: the app came back after a long absence.
        .onChange(of: appModel.selectedHour) { _, hour in
            sliderHour = Double(hour)
            model.dismissBestPickMessage()
        }
        .onChange(of: appModel.selectedLocationID) {
            model.dismissBestPickMessage()
            guard let location = appModel.selectedLocation else { return }
            region = model.flyTo(location)
            regionChange += 1
        }
        .onChange(of: model.gyms.isEmpty, initial: true) {
            if let region = model.regionForFirstFit() {
                self.region = region
                regionChange += 1
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
            SelectedGymCard(
                gym: gym,
                onDismiss: { model.clearSelection() },
                onOpen: { onOpenGym(gym) }
            )
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

    private func showBestPick() {
        Task {
            guard let region = await model.findBestPick() else { return }
            self.region = region
            regionChange += 1
        }
    }

    @ViewBuilder
    private var bestPickBanner: some View {
        if let message = model.bestPickMessage {
            HStack(spacing: 12) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Button("OK") { model.dismissBestPickMessage() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.brandPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.14), radius: 24, y: 8)
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
    MapView(model: MapViewModel(appModel: AppModel(apiClient: apiClient)))
}
