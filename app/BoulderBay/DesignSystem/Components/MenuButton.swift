import SwiftUI

extension EnvironmentValues {
    /// Opens the side menu. `AppShell` sets it for its root screens; without it (previews,
    /// snapshots) `MenuButton` does nothing.
    @Entry var openDrawer: (@MainActor @Sendable () -> Void)? = nil
}

/// The hamburger button at the top leading corner of each root screen (Map, Rankings, Gyms).
///
/// Drawn as the mockup's (`Boulder Bay.html`) 44pt white circle with three bars, rather than
/// a navigation-bar item, since the root screens draw their own headers.
struct MenuButton: View {
    @Environment(\.openDrawer) private var openDrawer

    var body: some View {
        Button {
            openDrawer?()
        } label: {
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.textPrimary)
                        .frame(width: 18, height: 2.5)
                }
            }
            .frame(width: 44, height: 44)
            // Translucent over the map, near white over the chalk background.
            .background(Theme.card.opacity(0.9), in: Circle())
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: Theme.shadow.opacity(0.08), radius: 1, y: 1)
            .shadow(color: Theme.shadow.opacity(0.12), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menu")
    }
}

#Preview {
    MenuButton()
        .padding()
        .background(Theme.background)
}
