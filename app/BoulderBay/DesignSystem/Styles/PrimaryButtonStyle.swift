import SwiftUI

/// Forest green, 52pt, r16, green shadow — the few primary actions (sign in, website).
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.bodyEmphasis)
            .foregroundStyle(Theme.onBrandPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                configuration.isPressed ? Theme.brandPrimaryHover : Theme.brandPrimary,
                in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
            )
            .shadow(color: Theme.brandPrimary.opacity(0.22), radius: 12, y: 8)
    }
}

/// White with an inset hairline — secondary actions (sign waiver).
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.bodyEmphasis)
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                configuration.isPressed ? Theme.surface : Theme.card,
                in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.1))
            )
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

#Preview {
    VStack(spacing: 12) {
        Button("Sign in") {}.buttonStyle(.primary)
        HStack(spacing: 10) {
            Button("Website") {}.buttonStyle(PrimaryButtonStyle(height: 50))
            Button("Sign waiver") {}.buttonStyle(SecondaryButtonStyle(height: 50))
        }
    }
    .padding()
    .background(Theme.background)
}
