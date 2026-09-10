import SwiftUI

/// The white card: level word and capacity on the left, best time on the right, the
/// progress bar, then the hourly chart.
struct BusynessCard: View {
    let model: GymDetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.nowLabel)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Text(model.level?.label ?? "Closed")
                        .font(Typography.display)
                        .tightTracking()
                        .foregroundStyle(model.level.map { Theme.Busyness.color(for: $0) } ?? Theme.textTertiary)
                    Text(model.capacityText)
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Best time to go")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Text(model.bestTimeText)
                        .font(Typography.headlineMedium)
                        .foregroundStyle(Theme.textPrimary)
                    Text(model.bestNoteText)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .multilineTextAlignment(.trailing)
            }

            GeometryReader { proxy in
                Capsule().fill(Theme.surface)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(model.level.map { Theme.Busyness.color(for: $0) } ?? Theme.textTertiary)
                            .frame(width: proxy.size.width * CGFloat(model.busyPct ?? 0) / 100)
                    }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.3), value: model.busyPct)

            if model.bars.isEmpty {
                Text("No forecast for today.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForecastChart(bars: model.bars, ticks: model.ticks)
            }
        }
        .card()
    }
}
