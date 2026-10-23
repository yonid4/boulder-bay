import SwiftUI

/// One gym on the map: a dot, and — zoomed in — a small card above it.
///
/// Geometry follows the mockup (`Boulder Bay.html`): a 14pt dot with a white ring, and a
/// label card that "leads with the word, not the number". The card shows the gym name and
/// its busyness line ("Quiet · 32%"), and the dot takes the crowd level's color. A gym
/// with no reading — closed, or open without a forecast — keeps a stone dot. The mockup's
/// busyness bar is not built yet.
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
            // Stone: "we have no crowd reading".
            .fill(levelColor ?? Theme.borderSolid)
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
            Text(MapViewModel.busynessLabel(for: gym))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor)
                // "Moderate · 55% · Live" is the longest line; shrink it rather than wrap.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                // Without its ideal height the line is shrunk even when it fits.
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: 118)
        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.08), radius: 1, y: 1)
        .shadow(color: Theme.shadow.opacity(0.16), radius: 12, y: 4)
    }

    /// The crowd level's color, or `nil` when the gym has no reading to color by.
    private var levelColor: Color? {
        gym.busyness.isOpen ? gym.busyness.level.map { Theme.Busyness.color(for: $0) } : nil
    }

    /// The busyness line's color: the level, else green for open and grey for closed.
    private var statusColor: Color {
        levelColor ?? (gym.busyness.isOpen ? Theme.Busyness.quiet : Theme.textTertiary)
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
    func gym(
        _ name: String,
        isOpen: Bool,
        busyPct: Int? = nil,
        level: BusynessLevel? = nil,
        source: BusynessSource? = nil
    ) -> Gym {
        Gym(
            slug: name.lowercased(),
            name: name,
            brand: .touchstone,
            city: "San Francisco",
            latitude: 37.7567,
            longitude: -122.3903,
            logoUrl: nil,
            isMember: false,
            busyness: ResolvedBusyness(
                at: .now, isOpen: isOpen, busyPct: busyPct, level: level, source: source
            )
        )
    }

    return HStack(spacing: 40) {
        GymPinView(
            gym: gym("Dogpatch Boulders", isOpen: true, busyPct: 32, level: .quiet, source: .live),
            isSelected: false,
            showsLabel: true
        )
        GymPinView(
            gym: gym("Mission Cliffs", isOpen: true, busyPct: 81, level: .packed, source: .forecast),
            isSelected: false,
            showsLabel: true
        )
        GymPinView(gym: gym("Mosaic", isOpen: false), isSelected: true, showsLabel: true)
        GymPinView(gym: gym("Mission", isOpen: true), isSelected: false, showsLabel: false)
    }
    .padding(60)
    .background(Theme.background)
}
