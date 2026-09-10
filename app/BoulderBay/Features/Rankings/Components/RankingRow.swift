import SwiftUI

/// Rows 2–8: rank, logo, name (+ Member), travel and city, level word and percent.
struct RankingRow: View {
    let ranked: RankedGym
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("\(ranked.rank)")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22)
                GymLogoView(gym: ranked.gym, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(ranked.gym.name)
                            .font(Typography.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if ranked.entry.isMember { MemberBadge(compact: true) }
                    }
                    HStack(spacing: 10) {
                        Text("\(ranked.entry.travelMinutes) min away")
                            .foregroundStyle(Theme.textSecondary)
                        Text(ranked.gym.city)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .font(Typography.footnote)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                BusynessBadge(percent: ranked.entry.busyPct, variant: .row)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 0) {
        RankingRow(ranked: RankedGym(
            entry: RankingEntry(slug: "hyperion", rank: 2, score: 61, busyPct: 58, isOpen: true, isMember: false, travelMinutes: 9, distanceMiles: 2.1),
            gym: PreviewData.gym("hyperion")
        )) {}
        RankingRow(ranked: RankedGym(
            entry: RankingEntry(slug: "mv-sf", rank: 3, score: 50, busyPct: 74, isOpen: true, isMember: true, travelMinutes: 41, distanceMiles: 30),
            gym: PreviewData.gym("mv-sf")
        )) {}
        RankingRow(ranked: RankedGym(
            entry: RankingEntry(slug: "mosaic", rank: 4, score: -5, busyPct: nil, isOpen: false, isMember: false, travelMinutes: 48, distanceMiles: 31),
            gym: PreviewData.mosaic
        )) {}
    }
    .padding()
    .background(Theme.background)
}
