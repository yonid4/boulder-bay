import SwiftUI

/// Everything under the Rankings header, drawn from values so snapshots can draw it.
struct RankingsContent: View {
    let phase: RankingsViewModel.Phase
    let memberships: Set<String>
    /// The selected place's label.
    let place: String
    let hour: Int
    let isNow: Bool
    let onRefresh: () async -> Void
    let onOpenGym: (Gym) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch phase {
                case .loading:
                    ProgressView()
                        .padding(.top, 120)
                case .failed(let message):
                    failure(message)
                case .loaded(let rankings, let refreshError):
                    if let refreshError { refreshBanner(refreshError) }
                    list(rankings.rankedGyms)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await onRefresh() }
    }

    @ViewBuilder
    private func list(_ rankedGyms: [RankedGym]) -> some View {
        if let best = rankedGyms.first {
            BestPickCard(
                rankedGym: best,
                isMember: memberships.contains(best.gym.slug),
                title: RankingsFormat.bestPickTitle(hour: hour, isNow: isNow),
                why: RankingsFormat.why(
                    rankedGym: best,
                    isMember: memberships.contains(best.gym.slug),
                    place: place,
                    hour: hour,
                    isNow: isNow
                ),
                onOpen: { onOpenGym(best.gym) }
            )
            .padding(.bottom, 8)
            ForEach(rankedGyms.dropFirst(), id: \.gym.id) { rankedGym in
                RankedGymRow(
                    rankedGym: rankedGym,
                    isMember: memberships.contains(rankedGym.gym.slug),
                    onOpen: { onOpenGym(rankedGym.gym) }
                )
            }
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text(RankingsFormat.emptyTitle(near: place, hour: hour, isNow: isNow))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Rankings list open gyms within 50 miles. Try another time or place.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.top, 120)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            retryButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 120)
    }

    private func refreshBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            retryButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Theme.shadow.opacity(0.08), radius: 16, y: 6)
        }
        .padding(.bottom, 12)
    }

    private var retryButton: some View {
        Button("Retry") { Task { await onRefresh() } }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.brandPrimary)
    }
}

/// Rank 1, on forest green.
struct BestPickCard: View {
    let rankedGym: RankedGym
    let isMember: Bool
    let title: String
    let why: String
    let onOpen: () -> Void

    private var gym: Gym { rankedGym.gym }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.onBrandPrimaryMuted)
                HStack(spacing: 14) {
                    LogoImage(gym: gym, size: 52, tint: Theme.onBrandPrimaryIcon)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(gym.name)
                                .font(.system(size: 20, weight: .bold))
                                .tracking(-0.2)
                                .foregroundStyle(Theme.onBrandPrimary)
                                .lineLimit(2)
                            if isMember { memberTag }
                        }
                        Text(why)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.onBrandPrimaryMuted)
                    }
                    Spacer(minLength: 0)
                }
                Rectangle()
                    .fill(Theme.onBrandPrimary.opacity(0.16))
                    .frame(height: 1)
                HStack(spacing: 8) {
                    Circle()
                        .fill(levelColor)
                        .frame(width: 10, height: 10)
                    Text(RankingsFormat.busynessWord(gym.busyness))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(levelColor)
                    if let percent = gym.busyness.busyPct {
                        Text("\(percent)% full")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.onBrandPrimaryMuted)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    Text(RankingsFormat.travel(minutes: rankedGym.travelMinutes))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.onBrandPrimaryMuted)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.brandPrimary)
                    .shadow(color: Theme.brandPrimary.opacity(0.28), radius: 32, y: 12)
            }
        }
        .buttonStyle(.plain)
    }

    private var levelColor: Color {
        gym.busyness.level.map { Theme.Busyness.color(for: $0, onDark: true) } ?? Theme.onBrandPrimary
    }

    private var memberTag: some View {
        Text("Member")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.clayOnDark)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Theme.clayOnDark.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}

/// Ranks 2 and on.
struct RankedGymRow: View {
    let rankedGym: RankedGym
    let isMember: Bool
    let onOpen: () -> Void

    private var gym: Gym { rankedGym.gym }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Text("\(rankedGym.rank)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                    .frame(width: 22)
                LogoImage(gym: gym, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(gym.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if isMember { memberTag }
                    }
                    HStack(spacing: 10) {
                        Text(RankingsFormat.travel(minutes: rankedGym.travelMinutes))
                            .foregroundStyle(Theme.textSecondary)
                        Text(gym.city)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(RankingsFormat.busynessWord(gym.busyness))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(levelColor)
                    if let percent = gym.busyness.busyPct {
                        Text("\(percent)%")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.divider).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var levelColor: Color {
        gym.busyness.level.map { Theme.Busyness.color(for: $0) } ?? Theme.textSecondary
    }

    private var memberTag: some View {
        Text("Member")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.clayText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Theme.clayBadgeTint,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
    }
}
