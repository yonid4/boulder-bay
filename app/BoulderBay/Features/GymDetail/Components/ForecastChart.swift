import Charts
import SwiftUI

/// The day's busyness as one bar per open hour, with a level legend, following the mockup.
///
/// Bars are placed by their start and end times, not by hour index, so a 23- or 25-hour DST day
/// still draws correctly. An hour with no reading keeps its slot and draws no bar.
struct ForecastChart: View {
    let forecast: BusynessForecast
    /// The hour the screen is showing (`gym.busyness.at`).
    let at: Date
    /// The current time. Hours that have ended by then are dimmed.
    let now: Date

    /// The tallest possible bar, from `ForecastBar.height`.
    private static let plotHeight = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let first = forecast.points.first, let last = forecast.points.last {
                chart(domain: first.startsAt...last.endsAt)
            }
            legend
        }
    }

    private func chart(domain: ClosedRange<Date>) -> some View {
        Chart(GymDetailFormat.forecastBars(forecast, at: at, now: now)) { bar in
            RectangleMark(
                xStart: .value("Start", bar.start),
                xEnd: .value("End", bar.end),
                yStart: .value("Base", 0),
                yEnd: .value("Busyness", bar.height)
            )
            .cornerRadius(3)
            .foregroundStyle(Theme.Busyness.color(for: bar.level).opacity(bar.opacity))
            .accessibilityLabel(bar.hourLabel)
            .accessibilityValue(bar.valueLabel)
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...Self.plotHeight)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: GymDetailFormat.forecastTicks(forecast)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel(anchor: .top) {
                        Text(GymDetailFormat.hourLabel(for: date, timeZone: forecast.timezone))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                            // The labels at the ends would otherwise truncate.
                            .fixedSize()
                    }
                }
            }
        }
        // About 84pt of plot, plus the row of hour labels.
        .frame(height: 104)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Quiet", color: Theme.Busyness.quiet)
            legendItem("Moderate", color: Theme.Busyness.moderate)
            legendItem("Packed", color: Theme.Busyness.packed)
            Spacer(minLength: 0)
            Text("Predicted until close")
                .foregroundStyle(Theme.textTertiary)
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
        }
    }
}
