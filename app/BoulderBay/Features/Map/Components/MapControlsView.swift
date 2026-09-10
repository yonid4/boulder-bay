import SwiftUI

/// The chrome over the map: menu button and location label on the first row, the time
/// chip and best-pick pill on the second, and the scrubber when the chip is open.
struct MapControlsView: View {
    @Bindable var model: MapViewModel
    let onMenu: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 10) {
                MenuButton(action: onMenu)
                if let location = model.location {
                    GlassPill(height: 44, tone: .stone, horizontalPadding: 18) {
                        VStack(spacing: 1) {
                            Text(location.label)
                                .font(Typography.label)
                                .foregroundStyle(Theme.textPrimary)
                            if let address = location.address {
                                Text(address)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Rankings from \(location.label)")
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if model.plannableHours != nil {
                    TimeChip(label: model.timeChipLabel, isExpanded: model.isTimeOpen) { model.toggleTime() }
                }
                BestPickPill(label: model.bestLabel) { model.pickBest() }
            }
            if model.isTimeOpen, let range = model.plannableHours {
                TimeScrubberView(plannedHour: $model.plannedHour, range: range)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.isTimeOpen)
    }
}
