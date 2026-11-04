import SwiftUI

/// One gym on the Gyms screen: tapping the logo and text opens the gym, and the pill beside
/// them is a separate tap target that changes the membership.
struct GymRow: View {
    /// What the pill says. Search results use `.add` / `.added`; "Your gyms" uses `.remove`,
    /// as in the mockup (`Boulder Bay.html`).
    enum Action {
        case add
        case added
        case remove
    }

    let gym: Gym
    let action: Action
    /// A change for this gym is in flight, so the pill is disabled until it lands.
    var isPending = false
    let onOpen: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    LogoImage(gym: gym, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gym.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Text(gym.city)
                                .foregroundStyle(Theme.textSecondary)
                            Text(GymList.brandLabel(for: gym))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .font(.system(size: 12))
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggle) {
                pill
            }
            .buttonStyle(.plain)
            .disabled(isPending)
            .accessibilityLabel(accessibilityLabel)
        }
        .padding(.vertical, 12)
        .padding(.leading, 16)
        .padding(.trailing, 14)
    }

    private var pill: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(height: 32)
            // Circular: at this size a continuous capsule draws nubs at its sides.
            .background(background, in: Capsule(style: .circular))
            .overlay {
                if action == .remove {
                    Capsule(style: .circular).strokeBorder(Theme.danger.opacity(0.25))
                }
            }
            .fixedSize()
            // Reaches the 44pt minimum without making the 32pt pill look any bigger.
            .contentShape(Rectangle().inset(by: -6))
    }

    private var title: String {
        switch action {
        case .add: "Add"
        case .added: "Added"
        case .remove: "Remove"
        }
    }

    private var foreground: Color {
        switch action {
        case .add: Theme.onBrandPrimary
        case .added: Theme.textSecondary
        case .remove: Theme.danger
        }
    }

    private var background: Color {
        switch action {
        case .add: Theme.brandPrimary
        case .added: Theme.surface
        case .remove: Theme.background
        }
    }

    private var accessibilityLabel: String {
        switch action {
        case .add: "Add \(gym.name)"
        case .added: "\(gym.name) added. Remove it"
        case .remove: "Remove \(gym.name)"
        }
    }
}
