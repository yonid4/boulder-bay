import SwiftUI

/// The "Now ▾" / "6 PM ▾" pill that opens the scrubber. Glass on the map, solid white
/// on the Rankings header.
struct TimeChip: View {
    let label: String
    let isExpanded: Bool
    var glass = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassPill(tone: glass ? .white : .solidWhite) {
                HStack(spacing: 6) {
                    Text(label).font(Typography.label).foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose time")
        .accessibilityValue(label)
    }
}

/// The hour slider: "Now" on the left, "10 PM" on the right, one-hour steps. Binding
/// nil means "now"; the parent (RankingStore) normalises an hour ≤ now back to nil.
struct TimeScrubberView: View {
    @Binding var plannedHour: Int?
    let range: ClosedRange<Int>
    var glass = true

    var body: some View {
        GlassPill(height: 44, tone: glass ? .white : .solidWhite, horizontalPadding: 16) {
            HStack(spacing: 12) {
                Text("Now").font(Typography.captionEmphasis).foregroundStyle(Theme.textSecondary)
                Slider(
                    value: Binding(
                        get: { Double(plannedHour ?? range.lowerBound) },
                        set: { plannedHour = Int($0.rounded()) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                .tint(Theme.brandPrimary)
                .accessibilityLabel("Hour")
                Text(Format.hour(range.upperBound))
                    .font(Typography.captionEmphasis)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    struct Demo: View {
        @State private var hour: Int? = 19
        var body: some View {
            VStack(spacing: 12) {
                HStack {
                    TimeChip(label: hour.map(Format.hour) ?? "Now", isExpanded: true) {}
                    TimeChip(label: "Now", isExpanded: false, glass: false) {}
                }
                TimeScrubberView(plannedHour: $hour, range: 17...22)
                TimeScrubberView(plannedHour: $hour, range: 17...22, glass: false)
            }
            .padding()
            .background(Theme.surface)
        }
    }
    return Demo()
}
