import SwiftUI

/// The frosted capsule the map controls sit in: translucent white over a blur, a
/// warm shadow. `tone: .stone` is the darker variant behind the location pills.
struct GlassPill<Content: View>: View {
    enum Tone {
        case white, stone, solidWhite
    }

    var height: CGFloat = 34
    var tone: Tone = .white
    var horizontalPadding: CGFloat = 14
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background {
                switch tone {
                case .white:
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Theme.card.opacity(0.85))
                case .stone:
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Theme.surface.opacity(0.9))
                case .solidWhite:
                    Capsule().fill(Theme.card)
                }
            }
            .shadow(color: Theme.shadow.opacity(0.08), radius: 1, y: 1)
            .shadow(color: Theme.shadow.opacity(0.14), radius: 12, y: 8)
    }
}

/// The round hamburger button — 44pt white circle, three ink bars.
struct MenuButton: View {
    var glass = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ForEach(0..<3) { _ in
                    Capsule().fill(Theme.textPrimary).frame(width: 18, height: 2.5)
                }
            }
            .frame(width: 44, height: 44)
            .background {
                if glass {
                    Circle().fill(.ultraThinMaterial)
                    Circle().fill(Theme.card.opacity(0.85))
                } else {
                    Circle().fill(Theme.card)
                }
            }
            .shadow(color: Theme.shadow.opacity(0.08), radius: 1, y: 1)
            .shadow(color: Theme.shadow.opacity(glass ? 0.14 : 0.1), radius: glass ? 12 : 9, y: glass ? 8 : 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menu")
    }
}

/// The round "‹" button on the detail screen.
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, height: 40)
                .background(Theme.card, in: Circle())
                .shadow(color: Theme.shadow.opacity(0.08), radius: 1, y: 1)
                .shadow(color: Theme.shadow.opacity(0.1), radius: 9, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [Theme.surface, Theme.background], startPoint: .top, endPoint: .bottom)
        VStack(spacing: 16) {
            HStack {
                MenuButton {}
                GlassPill(height: 44, tone: .stone) { Text("Home").font(Typography.label) }
                BackButton {}
            }
            GlassPill { Text("Now ▾").font(Typography.label) }
            GlassPill(tone: .solidWhite) { Text("6 PM ▾").font(Typography.label) }
        }
    }
}
