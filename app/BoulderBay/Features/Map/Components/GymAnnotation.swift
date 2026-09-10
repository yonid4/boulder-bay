import SwiftUI

/// A gym on the map: a 14pt dot in its level color with a white ring — a clay ring on
/// top for member gyms — and, when zoomed in, a small card above it that leads with
/// the level word. Grows 1.25× when selected.
struct GymAnnotation: View {
    let pin: MapPin
    let isSelected: Bool
    let showChip: Bool
    let action: () -> Void

    private var color: Color {
        pin.level.map { Theme.Busyness.color(for: $0) } ?? Theme.textTertiary
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                if showChip {
                    GymBusynessChip(pin: pin, color: color)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
                ZStack {
                    if pin.isMember {
                        Circle().fill(Theme.clay).frame(width: 22, height: 22)
                    }
                    Circle().fill(Theme.card).frame(width: 18, height: 18)
                    Circle().fill(color).frame(width: 14, height: 14)
                }
                .shadow(color: Theme.shadow.opacity(0.3), radius: 3, y: 2)
                .scaleEffect(isSelected ? 1.25 : 1)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: showChip)
        .accessibilityLabel(pin.gym.name)
        .accessibilityValue(pin.level.map { "\($0.label), \(pin.busyPct ?? 0)% full" } ?? "Closed")
    }
}

/// The 62pt card above a zoomed-in pin: level word and percent over a thin bar.
struct GymBusynessChip: View {
    let pin: MapPin
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            BusynessBadge(percent: pin.busyPct, variant: .chip)
            GeometryReader { proxy in
                Capsule().fill(Theme.surface)
                    .overlay(alignment: .leading) {
                        Capsule().fill(color)
                            .frame(width: proxy.size.width * CGFloat(pin.busyPct ?? 0) / 100)
                    }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: 62)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.08), radius: 1, y: 1)
        .shadow(color: Theme.shadow.opacity(0.16), radius: 6, y: 4)
        .overlay(alignment: .bottom) {
            Triangle().fill(Theme.card).frame(width: 8, height: 4).offset(y: 4)
        }
        .padding(.bottom, 8)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// "You are here": a blue dot with a white ring and a pulsing halo.
struct LocationDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.locationDot.opacity(0.45))
                .frame(width: 32, height: 32)
                .scaleEffect(pulsing ? 2.6 : 1)
                .opacity(pulsing ? 0 : 0.45)
                .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false), value: pulsing)
            Circle().fill(Theme.card).frame(width: 22, height: 22)
            Circle().fill(Theme.locationDot).frame(width: 16, height: 16)
                .shadow(color: Theme.locationDot.opacity(0.45), radius: 4, y: 2)
        }
        .onAppear { pulsing = true }
        .accessibilityLabel("Your location")
    }
}

#Preview {
    let pin = MapPin(gym: PreviewData.dogpatch, busyPct: 54, isOpen: true, isMember: true, travelMinutes: 12, score: 60)
    let quiet = MapPin(gym: PreviewData.mosaic, busyPct: 18, isOpen: true, isMember: false, travelMinutes: 30, score: 50)
    let closed = MapPin(gym: PreviewData.belmont, busyPct: nil, isOpen: false, isMember: false, travelMinutes: 10, score: 0)
    return HStack(spacing: 40) {
        GymAnnotation(pin: pin, isSelected: true, showChip: true) {}
        GymAnnotation(pin: quiet, isSelected: false, showChip: true) {}
        GymAnnotation(pin: closed, isSelected: false, showChip: false) {}
        LocationDot()
    }
    .padding(60)
    .background(Theme.surface)
}
