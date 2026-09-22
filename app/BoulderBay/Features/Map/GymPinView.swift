import SwiftUI

/// One gym on the map: a dot, and — zoomed in — a small card above it.
///
/// Geometry follows the mockup (`Boulder Bay.html`): a 14pt dot with a white ring, and a
/// label card that "leads with the word, not the number". The mockup's word is the crowd
/// level and its card carries a busyness bar; neither exists yet (the API returns
/// `busy_pct`/`level` as null until the scraper lands), so the card leads with the gym name
/// and its open state, and the dot is stone rather than a crowd color.
struct GymPinView: View {
    let gym: Gym
    let isSelected: Bool
    let showsLabel: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsLabel {
                label
                pointer
            }
            dot
        }
        .scaleEffect(isSelected ? 1.25 : 1, anchor: .bottom)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: showsLabel)
    }

    private var dot: some View {
        Circle()
            // Stone: "we have no crowd reading". Becomes
            // `Theme.Busyness.color(forPercent:)` once busy_pct is populated.
            .fill(Theme.borderSolid)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: Theme.shadow.opacity(0.3), radius: 3, y: 2)
    }

    private var label: some View {
        VStack(spacing: 2) {
            Text(gym.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                // Bay Area gym names are long; wrapping beats "Dogpatch Boulde…".
                .lineLimit(2)
                .multilineTextAlignment(.center)
                // Inside a map annotation the text is laid out at its ideal width, so it
                // truncates unless it is allowed to grow downwards inside a fixed frame.
                .fixedSize(horizontal: false, vertical: true)
            Text(MapViewModel.openStateLabel(for: gym))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(gym.busyness.isOpen ? Theme.Busyness.quiet : Theme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: 118)
        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.08), radius: 1, y: 1)
        .shadow(color: Theme.shadow.opacity(0.16), radius: 12, y: 4)
    }

    /// The card's little tail, pointing down at the dot.
    private var pointer: some View {
        Triangle()
            .fill(.white)
            .frame(width: 8, height: 4)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("Pins") {
    func gym(_ name: String, isOpen: Bool) -> Gym {
        Gym(
            slug: name.lowercased(),
            name: name,
            brand: .touchstone,
            city: "San Francisco",
            latitude: 37.7567,
            longitude: -122.3903,
            logoUrl: nil,
            busyness: ResolvedBusyness(
                at: .now, isOpen: isOpen, busyPct: nil, level: nil, source: nil
            )
        )
    }

    return HStack(spacing: 40) {
        GymPinView(gym: gym("Dogpatch Boulders", isOpen: true), isSelected: false, showsLabel: true)
        GymPinView(gym: gym("Mosaic", isOpen: false), isSelected: true, showsLabel: true)
        GymPinView(gym: gym("Mission", isOpen: true), isSelected: false, showsLabel: false)
    }
    .padding(60)
    .background(Theme.background)
}
