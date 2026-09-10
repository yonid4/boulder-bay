import SwiftUI

/// Placeholder until the drawer lands: proves the gate reaches the signed-in app.
struct AppShellView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: 16) {
            Text("Signed in as \(container.auth.session.user?.email ?? "?")")
                .font(Typography.body)
                .foregroundStyle(Theme.textPrimary)
            Text("Rankings from \(container.locations.current?.label ?? "?")")
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
            Button("Sign out") { Task { await container.signOut() } }
                .buttonStyle(.secondary)
                .frame(width: 160)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
