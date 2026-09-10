import SwiftUI

/// Hamburger + 30pt title (+ optional subtitle) + an optional trailing control, the way
/// Rankings and Gyms open. Sits at the mockup's top inset; the parent supplies padding.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let onMenu: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        onMenu: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onMenu = onMenu
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Spacing.stack) {
            MenuButton(glass: false, action: onMenu)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.screenTitle)
                    .tightTracking()
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        ScreenHeader(title: "Rankings", subtitle: "Live, 5 PM", onMenu: {}) {
            TimeChip(label: "Now", isExpanded: false, glass: false) {}
        }
        ScreenHeader(title: "Gyms", onMenu: {})
    }
    .padding(Spacing.header)
    .background(Theme.background)
}
