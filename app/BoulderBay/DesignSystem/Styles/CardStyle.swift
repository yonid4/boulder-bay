import SwiftUI

/// A white card floating on chalk: r24, warm shadow. The detail screen's busyness card
/// and the Gyms lists use it.
struct CardStyle: ViewModifier {
    var radius: CGFloat = Radius.card
    var padding: CGFloat? = Spacing.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(.all, padding ?? 0)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.06), radius: 1, y: 1)
            .shadow(color: Theme.shadow.opacity(0.08), radius: 15, y: 10)
    }
}

extension View {
    func card(radius: CGFloat = Radius.card, padding: CGFloat? = Spacing.cardPadding) -> some View {
        modifier(CardStyle(radius: radius, padding: padding))
    }

    /// The lighter shadow the mockup uses on lists and pills.
    func floatingShadow() -> some View {
        shadow(color: Theme.shadow.opacity(0.06), radius: 1, y: 1)
            .shadow(color: Theme.shadow.opacity(0.06), radius: 10, y: 6)
    }
}
