import SwiftUI

/// Color tokens for Boulder Bay, extracted from the Claude Design mockup
/// (`Boulder Bay.html`, the source of truth for UI/nav — see root `CLAUDE.md`)
/// and cross-checked against the "Visual design" section of `boulder_bay_plan.md`.
///
/// The mockup's own direction note: "Warm chalk and stone, nothing dark but
/// text. Forest green for the few primary actions, white or stone for
/// secondary ones, clay for identity (avatar, app icon, member pin rings).
/// Amber and red belong to busyness alone." Every token below is grouped
/// under that intent.
///
/// The app ships light-mode only (`UIUserInterfaceStyle: Light` in
/// `Info.plist`), so these are plain `Color` values rather than dynamic
/// dark-aware assets. The mockup's frosted-glass chrome (map pill controls)
/// is a `backdrop-filter: blur` over translucent white — reach for
/// `.ultraThinMaterial`/`.regularMaterial` for that in SwiftUI rather than a
/// fixed color.
enum Theme {

    // MARK: Background & surface

    /// Base screen background — warm chalk.
    static let background = Color(hex: 0xF5F2EC)

    /// Card / pill / row surface, one step warmer than `background`.
    /// Used for avatar-initial circles, progress-bar tracks, selected nav rows.
    static let surface = Color(hex: 0xEDE7DD)

    /// Elevated surface for panels above the background, e.g. the hamburger
    /// side menu.
    static let surfaceElevated = Color(hex: 0xFBF9F5)

    /// Card background floating on top of `background` (map cards, sheets,
    /// list rows, text fields).
    static let card = Color.white

    // MARK: Text

    static let textPrimary = Color(hex: 0x1F1B16)
    static let textSecondary = Color(hex: 0x6B6259)
    static let textTertiary = Color(hex: 0x9C9287)

    // MARK: Borders, dividers & shadow

    /// Hairline divider/border, drawn as a tint of `textPrimary` (the
    /// mockup uses this at opacities from 0.06 to 0.1 depending on context —
    /// use `Theme.textPrimary.opacity(_:)` directly to fine-tune).
    static let divider = textPrimary.opacity(0.08)

    /// Solid stone border/fill, e.g. the search field's clear button.
    static let borderSolid = Color(hex: 0xD9D2C6)

    /// Elevation shadow tint — warm near-black, not pure black. Use with
    /// `.shadow(color: Theme.shadow.opacity(_:), radius:, y:)`.
    static let shadow = Color(hex: 0x281E14)

    // MARK: Brand (forest green) — the few primary actions

    static let brandPrimary = Color(hex: 0x1F5C42)
    static let brandPrimaryHover = Color(hex: 0x2F7A5A)

    /// Text/icon on top of `brandPrimary`.
    static let onBrandPrimary = Color(hex: 0xF1F7F3)

    /// Secondary text on top of `brandPrimary` (e.g. "12 min away").
    static let onBrandPrimaryMuted = Color(hex: 0xA9D3BC)

    /// Avatar-initials text on top of `brandPrimary`.
    static let onBrandPrimaryIcon = Color(hex: 0xD5EADF)

    // MARK: Clay — identity (avatar, app icon, member pin rings)

    static let clay = Color(hex: 0xB8623A)

    /// Darker clay, for text on `clayTint`/`clayBadgeTint`.
    static let clayText = Color(hex: 0x8A5A3B)

    /// Pale clay tint for circular avatar/icon backgrounds.
    static let clayTint = clay.opacity(0.16)

    /// Pale clay tint for the "Member" badge background (a distinct, slightly
    /// warmer clay than `clayTint` in the mockup).
    static let clayBadgeTint = Color(hex: 0xB08968).opacity(0.18)

    /// Pale clay text, for use on dark/brand backgrounds (e.g. the "Member"
    /// badge on the best-pick card).
    static let clayOnDark = Color(hex: 0xF3DDBE)

    // MARK: Danger — destructive actions only (sign out, remove gym)

    /// Distinct from `Busyness.packed`; reserved for destructive actions,
    /// never for crowd levels.
    static let danger = Color(hex: 0xB8463F)

    // MARK: Busyness — amber and red belong to this alone

    enum Busyness {
        static let quiet = Color(hex: 0x2F9E66)
        static let quietOnDark = Color(hex: 0x7BD6A6)
        static let moderate = Color(hex: 0xC98A1E)
        static let moderateOnDark = Color(hex: 0xF0C061)
        static let packed = Color(hex: 0xD9534F)
        static let packedOnDark = Color(hex: 0xF28B87)

        /// The level's color, on chalk or on the forest-green best-pick card.
        static func color(for level: BusynessLevel, onDark: Bool = false) -> Color {
            switch level {
            case .quiet: onDark ? quietOnDark : quiet
            case .moderate: onDark ? moderateOnDark : moderate
            case .packed: onDark ? packedOnDark : packed
            }
        }

        /// Maps a 0–100 busyness percentage to its level color.
        static func color(forPercent percent: Int, onDark: Bool = false) -> Color {
            color(for: BusynessLevel(percent: percent), onDark: onDark)
        }
    }

    // MARK: Map

    /// "You are here" location dot.
    static let locationDot = Color(hex: 0x1A73E8)
}

#Preview("Theme swatches") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            swatchGroup("Background & surface", [
                ("background", Theme.background), ("surface", Theme.surface),
                ("surfaceElevated", Theme.surfaceElevated), ("card", Theme.card),
            ])
            swatchGroup("Text", [
                ("textPrimary", Theme.textPrimary), ("textSecondary", Theme.textSecondary),
                ("textTertiary", Theme.textTertiary),
            ])
            swatchGroup("Brand", [
                ("brandPrimary", Theme.brandPrimary), ("brandPrimaryHover", Theme.brandPrimaryHover),
                ("onBrandPrimary", Theme.onBrandPrimary), ("onBrandPrimaryMuted", Theme.onBrandPrimaryMuted),
                ("onBrandPrimaryIcon", Theme.onBrandPrimaryIcon),
            ])
            swatchGroup("Clay", [
                ("clay", Theme.clay), ("clayText", Theme.clayText),
                ("clayTint", Theme.clayTint), ("clayBadgeTint", Theme.clayBadgeTint),
                ("clayOnDark", Theme.clayOnDark),
            ])
            swatchGroup("Busyness", [
                ("quiet", Theme.Busyness.quiet), ("quietOnDark", Theme.Busyness.quietOnDark),
                ("moderate", Theme.Busyness.moderate), ("moderateOnDark", Theme.Busyness.moderateOnDark),
                ("packed", Theme.Busyness.packed), ("packedOnDark", Theme.Busyness.packedOnDark),
            ])
            swatchGroup("Other", [
                ("danger", Theme.danger), ("locationDot", Theme.locationDot),
                ("borderSolid", Theme.borderSolid), ("shadow", Theme.shadow),
            ])
        }
        .padding()
    }
    .background(Theme.background)
}

private func swatchGroup(_ title: String, _ swatches: [(String, Color)]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
        ForEach(swatches, id: \.0) { name, color in
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
                    .frame(width: 32, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.divider))
                Text(name).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
