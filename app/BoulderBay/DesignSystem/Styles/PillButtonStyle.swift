import SwiftUI

/// The small capsule buttons on Gyms rows: Add (green), Added (stone), Remove (danger).
struct PillButtonStyle: ButtonStyle {
    enum Kind {
        case add, added, remove
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.label)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(background, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    kind == .remove ? Theme.danger.opacity(0.25) : .clear
                )
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var background: Color {
        switch kind {
        case .add: Theme.brandPrimary
        case .added: Theme.surface
        case .remove: Theme.background
        }
    }

    private var foreground: Color {
        switch kind {
        case .add: Theme.onBrandPrimary
        case .added: Theme.textSecondary
        case .remove: Theme.danger
        }
    }
}

#Preview {
    HStack(spacing: 10) {
        Button("Add") {}.buttonStyle(PillButtonStyle(kind: .add))
        Button("Added") {}.buttonStyle(PillButtonStyle(kind: .added))
        Button("Remove") {}.buttonStyle(PillButtonStyle(kind: .remove))
    }
    .padding()
    .background(Theme.card)
}
