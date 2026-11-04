import SwiftUI

/// The Rankings screen: the best gym for the selected place and hour, and the rest in order.
struct RankingsView: View {
    private let appModel: AppModel
    private let onOpenGym: (Gym) -> Void

    @State private var model: RankingsViewModel
    @State private var isTimeOpen = false
    /// The slider's live value. The selected hour, and the refetch, only follow once a drag ends.
    @State private var sliderHour: Double
    @State private var isDraggingHour = false

    init(appModel: AppModel, onOpenGym: @escaping (Gym) -> Void) {
        self.appModel = appModel
        self.onOpenGym = onOpenGym
        _model = State(initialValue: RankingsViewModel(appModel: appModel))
        _sliderHour = State(initialValue: Double(appModel.selectedHour))
    }

    var body: some View {
        VStack(spacing: 0) {
            RankingsHeader(
                // These follow the slider during a drag, while the list waits for it to end.
                timeLabel: RankingsFormat.timeLabel(
                    hour: Int(sliderHour), isNow: appModel.isCurrentHour(Int(sliderHour))
                ),
                timeChip: RankingsFormat.timeChip(
                    hour: Int(sliderHour), isNow: appModel.isCurrentHour(Int(sliderHour))
                ),
                locations: appModel.locationsInDisplayOrder,
                selected: appModel.selectedLocation,
                isTimeOpen: $isTimeOpen,
                sliderHour: $sliderHour,
                onSelectLocation: { appModel.selectLocation(id: $0.id) },
                onHourEditingChanged: { isEditing in
                    isDraggingHour = isEditing
                    if !isEditing { commitHour() }
                }
            )
            RankingsContent(
                phase: model.phase,
                memberships: appModel.memberships,
                place: appModel.selectedLocation?.label ?? "you",
                hour: appModel.selectedHour,
                isNow: appModel.isSelectedHourNow,
                onRefresh: { await model.load() },
                onOpenGym: onOpenGym
            )
        }
        .background(Theme.background)
        .task(id: model.selection) { await model.loadIfNeeded() }
        .onChange(of: appModel.liveRefreshCount) {
            Task { await model.load() }
        }
        // The hour moved without the slider: the app came back after a long absence.
        .onChange(of: appModel.selectedHour) { _, hour in
            sliderHour = Double(hour)
        }
        // VoiceOver adjustments change the value without a drag; commit those directly.
        .onChange(of: sliderHour) {
            if !isDraggingHour { commitHour() }
        }
    }

    private func commitHour() {
        let hour = Int(sliderHour)
        guard hour != appModel.selectedHour else { return }
        appModel.selectedHour = hour
    }
}

/// The title, the time and its slider, and the place.
struct RankingsHeader: View {
    let timeLabel: String
    let timeChip: String
    let locations: [SavedLocation]
    let selected: SavedLocation?
    @Binding var isTimeOpen: Bool
    @Binding var sliderHour: Double
    let onSelectLocation: (SavedLocation) -> Void
    let onHourEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                MenuButton()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rankings")
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(timeLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                timeButton
            }
            HStack(spacing: 0) {
                LocationSwitcher(
                    locations: locations,
                    selected: selected,
                    onSelect: onSelectLocation
                )
                Spacer(minLength: 0)
            }
            if isTimeOpen {
                hourSlider
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var timeButton: some View {
        Button {
            isTimeOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(timeChip)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.55)
                    .rotationEffect(.degrees(isTimeOpen ? 180 : 0))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background {
                Capsule(style: .circular)
                    .fill(Theme.card)
                    .shadow(color: Theme.shadow.opacity(0.1), radius: 18, y: 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose time")
        .accessibilityValue(timeChip)
    }

    private var hourSlider: some View {
        Slider(value: $sliderHour, in: 0...23, step: 1, onEditingChanged: onHourEditingChanged)
            .tint(Theme.brandPrimary)
            .accessibilityLabel("Time of day")
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background {
                Capsule(style: .circular)
                    .fill(Theme.card)
                    .shadow(color: Theme.shadow.opacity(0.1), radius: 18, y: 6)
            }
    }
}

#Preview {
    let apiClient = APIClient(accessToken: { "preview-token" })
    RankingsView(appModel: AppModel(apiClient: apiClient), onOpenGym: { _ in })
}
