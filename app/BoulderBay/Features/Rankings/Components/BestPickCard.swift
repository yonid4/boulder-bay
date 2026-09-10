import SwiftUI

/// The forest-green card at the top of Rankings: the best pick, why, and its busyness
/// on the on-dark palette. Logos render as a light-tinted template here.
struct BestPickCard: View {
    let ranked: RankedGym
    let label: String
    let why: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Text(label)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.onBrandPrimaryMuted)
                HStack(spacing: 14) {
                    GymLogoView(gym: ranked.gym, size: 52, style: .onDark)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(ranked.gym.name)
                                .font(Typography.titleSmall)
                                .foregroundStyle(Theme.onBrandPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if ranked.entry.isMember { MemberBadge(onDark: true) }
                        }
                        Text(why)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.onBrandPrimaryMuted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    BusynessBadge(percent: ranked.entry.busyPct, variant: .onDark)
                    Spacer(minLength: 8)
                    Text("\(ranked.entry.travelMinutes) min away")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.onBrandPrimaryMuted)
                }
                .padding(.top, 12)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.onBrandPrimary.opacity(0.16)).frame(height: 1)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.brandPrimary, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: Theme.brandPrimary.opacity(0.28), radius: 16, y: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens gym details")
    }
}

#Preview {
    let entry = RankingEntry(slug: "mv-belmont", rank: 1, score: 76, busyPct: 31, isOpen: true, isMember: true, travelMinutes: 12, distanceMiles: 4.2)
    return BestPickCard(
        ranked: RankedGym(entry: entry, gym: PreviewData.belmont),
        label: "Best pick right now",
        why: "Your gym, and it's quiet right now"
    ) {}
    .padding()
    .background(Theme.background)
}
