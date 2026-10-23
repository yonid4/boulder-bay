import SwiftUI

/// The card that slides up when a pin is tapped.
///
/// The mockup's version also carries the gym's logo and travel time. Neither is available
/// yet — no logo endpoint, no Mapbox client — so this shows what the gym list actually
/// returns: name, city and the busyness line, the line in its crowd level's color. It is deliberately not tappable; it opens gym detail
/// once that screen exists.
struct SelectedGymCard: View {
    let gym: Gym
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            monogram
            VStack(alignment: .leading, spacing: 3) {
                Text(gym.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                (Text("\(gym.city) · ")
                    + Text(MapViewModel.busynessLabel(for: gym))
                    .foregroundStyle(busynessColor))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(Theme.surface, in: Circle())
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.08), radius: 1, y: 1)
        .shadow(color: Theme.shadow.opacity(0.2), radius: 40, y: 16)
    }

    /// The crowd level's color; without a reading the line stays secondary text.
    private var busynessColor: Color {
        guard gym.busyness.isOpen, let level = gym.busyness.level else {
            return Theme.textSecondary
        }
        return Theme.Busyness.color(for: level)
    }

    /// Stands in for the gym's logo until `GET /api/gyms/{slug}/logo` serves bytes.
    private var monogram: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.surface)
            .frame(width: 48, height: 48)
            .overlay {
                Text(gym.name.prefix(1))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
    }
}

#Preview("Selected gym") {
    SelectedGymCard(
        gym: Gym(
            slug: "dogpatch",
            name: "Dogpatch Boulders",
            brand: .touchstone,
            city: "San Francisco",
            latitude: 37.7567,
            longitude: -122.3903,
            logoUrl: nil,
            isMember: false,
            busyness: ResolvedBusyness(
                at: .now, isOpen: true, busyPct: 32, level: .quiet, source: .live
            )
        ),
        onDismiss: {}
    )
    .padding(16)
    .background(Theme.background)
}
