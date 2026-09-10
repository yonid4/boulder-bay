import SwiftUI

/// 72pt logo, name, "Brand · Member".
struct GymHeaderView: View {
    let gym: Gym
    let isMember: Bool

    var body: some View {
        HStack(spacing: 16) {
            GymLogoView(gym: gym, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(gym.name)
                    .font(Typography.title)
                    .tightTracking()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(gym.brand.displayName)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if isMember { MemberBadge() }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    GymHeaderView(gym: PreviewData.belmont, isMember: true)
        .padding()
        .background(Theme.background)
}
