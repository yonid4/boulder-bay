import CoreGraphics

/// Corner radii from the mockup, named by what uses them.
enum Radius {
    static let pill: CGFloat = 999
    static let field: CGFloat = 14
    static let button: CGFloat = 16
    static let menuRow: CGFloat = 16
    static let userCard: CGFloat = 18
    static let listCard: CGFloat = 20
    static let mapCard: CGFloat = 22
    static let card: CGFloat = 24
    static let sheet: CGFloat = 28
    static let badge: CGFloat = 6
    static let chip: CGFloat = 10

    /// Logo chips scale their radius with their size (72→22, 52→16, 48→14, 38→11).
    static func logo(forSize size: CGFloat) -> CGFloat {
        (size * 0.3).rounded()
    }
}

enum Spacing {
    /// Horizontal inset for screen content.
    static let screen: CGFloat = 16
    /// Header inset — one step wider than content.
    static let header: CGFloat = 20
    static let cardPadding: CGFloat = 18
    static let rowPadding: CGFloat = 12
    static let stack: CGFloat = 14
    static let tight: CGFloat = 8
    static let hairline: CGFloat = 4
    /// Where the first control sits below the status bar on the map and headers.
    static let topChrome: CGFloat = 62
}
