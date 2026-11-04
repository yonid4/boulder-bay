import SwiftUI

/// The loaded detail screen's sections, separate from the view model so snapshots can draw them.
///
/// The order is design §9's; the styling follows the mockup (`Boulder Bay.html`): hairline
/// rows on the chalk background, with busyness on a white card.
struct GymDetailContent: View {
    let detail: GymDetail
    let isMember: Bool
    /// Whether the selected hour is the current one (`AppModel.isSelectedHourNow`).
    let isNow: Bool
    let onOpenInMaps: () -> Void

    @State private var isWeekExpanded: Bool

    init(
        detail: GymDetail,
        isMember: Bool,
        isNow: Bool,
        isWeekExpanded: Bool = false,
        onOpenInMaps: @escaping () -> Void = {}
    ) {
        self.detail = detail
        self.isMember = isMember
        self.isNow = isNow
        self.onOpenInMaps = onOpenInMaps
        _isWeekExpanded = State(initialValue: isWeekExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            VStack(spacing: 0) {
                addressRow
                if !detail.hours.isEmpty {
                    Rectangle().fill(Theme.divider).frame(height: 1)
                    hoursRow
                }
            }
            .padding(.horizontal, 4)
            busynessCard
            ratesRow
            links
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            LogoImage(gym: detail.gym, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.gym.name)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.48)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    Text("\(detail.gym.brand.rawValue.capitalized) · \(detail.gym.city)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    if isMember {
                        Text("Member")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.clayText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Theme.clayBadgeTint,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Address

    /// There's always somewhere to go: the coordinates aren't nullable, so a gym with no address
    /// still gets the row, naming its city.
    private var addressRow: some View {
        Button(action: onOpenInMaps) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    caption("Address")
                    Text(detail.address ?? detail.gym.city)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Open in Maps")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surface, in: Capsule())
                    .padding(.top, 2)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Hours

    private var today: LocalDate { detail.forecast.date }

    private var hoursRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isWeekExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        caption("Hours today")
                        Text(GymDetailFormat.todayHours(detail.hours, today: today))
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isWeekExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isWeekExpanded ? "Week shown" : "Week hidden")

            if isWeekExpanded {
                VStack(spacing: 6) {
                    ForEach(GymDetailFormat.week(detail.hours, today: today)) { day in
                        HStack {
                            Text(day.name)
                            Spacer(minLength: 12)
                            Text(day.text)
                        }
                        .font(.system(size: 14, weight: day.isToday ? .bold : .regular))
                        .foregroundStyle(day.isToday ? Theme.textPrimary : Theme.textSecondary)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.vertical, 14)
    }

    // MARK: Busyness

    private var busyness: BusynessSummary {
        GymDetailFormat.busyness(detail.gym.busyness, isNow: isNow, timeZone: detail.timezone)
    }

    private var busynessColor: Color {
        busyness.level.map { Theme.Busyness.color(for: $0) } ?? Theme.textSecondary
    }

    /// `nil` on a day with no open hours, when the card has neither a chart nor a best time.
    private var bestTime: BestTimeSummary? {
        GymDetailFormat.bestTime(detail.forecast, busyness: detail.gym.busyness, isNow: isNow)
    }

    private var busynessCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    caption(busyness.title)
                    Text(busyness.headline)
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(busynessColor)
                    if let line = busyness.detail {
                        Text(line)
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if let bestTime {
                    bestTimeColumn(bestTime)
                }
            }
            if let percent = busyness.percent {
                busynessBar(percent: percent)
            }
            if !detail.forecast.points.isEmpty {
                ForecastChart(forecast: detail.forecast, at: detail.gym.busyness.at)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.06), radius: 1, y: 1)
        .shadow(color: Theme.shadow.opacity(0.08), radius: 30, y: 10)
    }

    private func bestTimeColumn(_ bestTime: BestTimeSummary) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            caption("Best time to go")
            Text(bestTime.headline)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let note = bestTime.note {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .multilineTextAlignment(.trailing)
        .accessibilityElement(children: .combine)
    }

    private func busynessBar(percent: Int) -> some View {
        Capsule()
            .fill(Theme.surface)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(busynessColor)
                        .frame(width: proxy.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
                }
            }
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }

    // MARK: Rates

    @ViewBuilder
    private var ratesRow: some View {
        let lines = GymDetailFormat.rates(detail.rates)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                caption("Rates")
                ForEach([lines.dayPass, lines.monthly].compactMap(\.self), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Links

    @ViewBuilder
    private var links: some View {
        if detail.websiteUrl != nil || detail.waiverUrl != nil {
            HStack(spacing: 10) {
                if let url = detail.websiteUrl {
                    Link(destination: url) {
                        Text("Website")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.onBrandPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                Theme.brandPrimary,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .shadow(color: Theme.brandPrimary.opacity(0.22), radius: 24, y: 8)
                    }
                }
                if let url = detail.waiverUrl {
                    Link(destination: url) {
                        Text("Sign waiver")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                Theme.card,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Theme.textPrimary.opacity(0.1))
                            }
                    }
                }
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textTertiary)
    }
}
