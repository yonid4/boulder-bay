import SwiftUI

/// The user card at the foot of the drawer: clay-tint monogram, name, email, and a
/// chevron that opens the sign-out popover above it.
struct ProfileHeaderView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppShellViewModel.self) private var shell

    private var user: AuthUser? { container.auth.session.user }
    private var name: String { user?.displayName ?? user?.email.split(separator: "@").first.map(String.init) ?? "You" }

    var body: some View {
        VStack(spacing: 8) {
            if shell.isUserMenuOpen {
                Button {
                    Task { await container.signOut() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Sign out").font(Typography.body)
                    }
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Theme.shadow.opacity(0.08), radius: 1, y: 1)
                .shadow(color: Theme.shadow.opacity(0.18), radius: 16, y: 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
                shell.toggleUserMenu()
            } label: {
                HStack(spacing: 12) {
                    Text(name.initials)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.clayText)
                        .frame(width: 42, height: 42)
                        .background(Theme.clayTint, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(Typography.bodyEmphasis)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(user?.email ?? "")
                            .font(Typography.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(shell.isUserMenuOpen ? -90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.userCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.userCard, style: .continuous)
                    .strokeBorder(Theme.clay, lineWidth: shell.isUserMenuOpen ? 1.5 : 0)
            )
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: shell.isUserMenuOpen)
    }
}
