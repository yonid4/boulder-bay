import SwiftUI

/// The hourly bars for today: one per open hour, colored by that hour's level, past
/// hours faded and the current hour solid, with tick labels and the legend beneath.
struct ForecastChart: View {
    let bars: [GymDetailViewModel.Bar]
    let ticks: [Int]

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(bars) { bar in
                    UnevenRoundedRectangle(
                        topLeadingRadius: 3, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 3
                    )
                    .fill(Theme.Busyness.color(for: bar.level))
                    .opacity(bar.opacity)
                    .frame(height: 6 + CGFloat(bar.busyPct) * 0.78)
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .accessibilityLabel("\(Format.hour(bar.hour)): \(bar.level.label), \(bar.busyPct)%")
                }
            }
            .frame(height: 88, alignment: .bottom)

            HStack {
                ForEach(ticks, id: \.self) { hour in
                    Text(Format.hour(hour))
                    if hour != ticks.last { Spacer(minLength: 0) }
                }
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundStyle(Theme.textTertiary)

            HStack(spacing: 14) {
                ForEach(BusynessLevel.allCases, id: \.self) { level in
                    HStack(spacing: 5) {
                        Circle().fill(Theme.Busyness.color(for: level)).frame(width: 8, height: 8)
                        Text(level.label)
                    }
                }
                Spacer(minLength: 0)
                Text("Predicted until close").foregroundStyle(Theme.textTertiary)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
        }
    }
}

#Preview {
    let bars = (6..<23).map { hour in
        GymDetailViewModel.Bar(
            hour: hour,
            busyPct: MockBusyness.typicalPct(hour: hour, scale: 1),
            isCurrent: hour == 17, isPast: hour < 17
        )
    }
    return ForecastChart(bars: bars, ticks: [6, 10, 14, 18, 22])
        .padding()
        .card()
        .padding()
        .background(Theme.background)
}
