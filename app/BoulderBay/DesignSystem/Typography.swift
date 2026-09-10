import SwiftUI

/// Type sizes lifted from the mockup. The system font throughout; hierarchy comes from
/// size and weight, never from all-caps or tracking.
enum Typography {
    /// "Rankings", "Gyms" — 30pt bold, slightly tight.
    static let screenTitle = Font.system(size: 30, weight: .bold)
    /// Gym name on the detail screen, auth titles.
    static let title = Font.system(size: 24, weight: .bold)
    /// Best-pick gym name.
    static let titleSmall = Font.system(size: 20, weight: .bold)
    /// Side-menu rows.
    static let menuRow = Font.system(size: 19, weight: .semibold)
    /// Level word on the best-pick card, best-time window.
    static let headline = Font.system(size: 17, weight: .bold)
    static let headlineMedium = Font.system(size: 17, weight: .semibold)
    /// Gym name on the map card, text fields, buttons.
    static let bodyEmphasis = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 16)
    /// Gym name in rows, detail list values.
    static let rowTitle = Font.system(size: 15, weight: .semibold)
    static let rowBody = Font.system(size: 15)
    /// Rank numbers, pill buttons, chips.
    static let label = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 13)
    static let captionEmphasis = Font.system(size: 12, weight: .semibold)
    static let footnote = Font.system(size: 12)
    static let badge = Font.system(size: 11, weight: .semibold)
    static let micro = Font.system(size: 10, weight: .semibold)
    /// The huge level word on the detail card.
    static let display = Font.system(size: 30, weight: .bold)
}

extension View {
    /// The mockup's `-0.02em` on big titles.
    func tightTracking() -> some View {
        kerning(-0.5)
    }
}
