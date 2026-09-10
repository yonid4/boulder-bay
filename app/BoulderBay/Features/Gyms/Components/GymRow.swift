import SwiftUI

/// A gym in the Gyms lists: logo, name, "City · Brand", and a trailing pill — Add /
/// Added in results, Remove in your gyms. The row body opens the detail.
struct GymRow: View {
    enum Trailing {
        case add(isMember: Bool)
        case remove
    }

    let gym: Gym
    let trailing: Trailing
    let onOpen: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    GymLogoView(gym: gym, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gym.name)
                            .font(Typography.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Text(gym.city).foregroundStyle(Theme.textSecondary)
                            Text(gym.brand.displayName).foregroundStyle(Theme.textTertiary)
                        }
                        .font(Typography.footnote)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            switch trailing {
            case .add(let isMember):
                Button(isMember ? "Added" : "Add", action: onToggle)
                    .buttonStyle(PillButtonStyle(kind: isMember ? .added : .add))
                    .accessibilityLabel(isMember ? "Remove \(gym.name)" : "Add \(gym.name)")
            case .remove:
                Button("Remove", action: onToggle)
                    .buttonStyle(PillButtonStyle(kind: .remove))
                    .accessibilityLabel("Remove \(gym.name)")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.textPrimary.opacity(0.06)).frame(height: 1).padding(.leading, 16)
        }
    }
}

/// The white rounded container the rows sit in.
struct GymListCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.listCard, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Radius.listCard, style: .continuous))
            .floatingShadow()
    }
}

#Preview {
    VStack(spacing: 20) {
        GymListCard {
            GymRow(gym: PreviewData.gym("bm-sf"), trailing: .add(isMember: false), onOpen: {}, onToggle: {})
            GymRow(gym: PreviewData.gym("bm-berkeley"), trailing: .add(isMember: true), onOpen: {}, onToggle: {})
        }
        GymListCard {
            GymRow(gym: PreviewData.belmont, trailing: .remove, onOpen: {}, onToggle: {})
        }
    }
    .padding()
    .background(Theme.background)
}
