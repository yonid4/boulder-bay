import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Theme.onBrandPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                configuration.isPressed ? Theme.brandPrimaryHover : Theme.brandPrimary,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
