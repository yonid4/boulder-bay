import SwiftUI

/// The card that slides up when a pin is tapped: logo, name, Member badge, drive time
/// and open status, with the level word and percent on the right. Tapping it opens
/// the detail.
struct GymBusynessCard: View {
    let pin: MapPin
    let effectiveHour: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                GymLogoView(gym: pin.gym, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(pin.gym.name)
                            .font(Typography.bodyEmphasis)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if pin.isMember { MemberBadge() }
                    }
                    HStack(spacing: 12) {
                        if let minutes = pin.travelMinutes {
                            Text("\(minutes) min drive")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(Format.openStatus(hoursToday: pin.gym.hoursToday, at: effectiveHour))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .font(Typography.caption)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                BusynessBadge(percent: pin.busyPct, variant: .mapCard)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: Radius.mapCard, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: Radius.mapCard, style: .continuous).fill(Theme.card.opacity(0.92))
            }
            .shadow(color: Theme.shadow.opacity(0.08), radius: 1, y: 1)
            .shadow(color: Theme.shadow.opacity(0.2), radius: 20, y: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens gym details")
    }
}

/// The green "Best right now" capsule with its mint dot.
struct BestPickPill: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(Theme.Busyness.quietOnDark).frame(width: 8, height: 8)
                Text(label).font(Typography.label)
            }
            .foregroundStyle(Theme.onBrandPrimary)
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(height: 34)
            .background(Theme.brandPrimary, in: Capsule())
            .shadow(color: Theme.brandPrimary.opacity(0.25), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 20) {
        BestPickPill(label: "Best right now") {}
        GymBusynessCard(
            pin: MapPin(gym: PreviewData.belmont, busyPct: 41, isOpen: true, isMember: true, travelMinutes: 12, score: 70),
            effectiveHour: 17
        ) {}
        GymBusynessCard(
            pin: MapPin(gym: PreviewData.mosaic, busyPct: nil, isOpen: false, isMember: false, travelMinutes: 48, score: 0),
            effectiveHour: 3
        ) {}
    }
    .padding()
    .background(Theme.surface)
}
