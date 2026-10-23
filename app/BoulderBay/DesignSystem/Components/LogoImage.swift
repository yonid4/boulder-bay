import SwiftUI
import UIKit

extension EnvironmentValues {
    /// The app's one `LogoStore`. Without it — previews, snapshot tests — `LogoImage` shows
    /// its initials placeholder.
    @Entry var logoStore: LogoStore? = nil
}

/// A gym's logo in a rounded chip, loaded through the environment's `LogoStore`.
///
/// While the logo loads, and for good when the gym has none (`logoUrl` is null, or the route
/// 404s), the chip shows the gym's initials instead, as every chip in the mockup
/// (`Boulder Bay.html`) does. `tint` is for chips on a dark background, such as the best-pick
/// card: the logo and initials are drawn in it, over a faint wash of it.
struct LogoImage: View {
    let gym: Gym
    var size: CGFloat = 48
    var tint: Color? = nil

    @Environment(\.logoStore) private var store
    /// Keyed by slug, so a reused view never shows the previous gym's logo.
    @State private var loaded: (slug: String, image: UIImage)?

    var body: some View {
        LogoChip(
            name: gym.name,
            image: loaded?.slug == gym.slug ? loaded?.image : nil,
            size: size,
            tint: tint
        )
        .task(id: gym.slug) {
            // A null `logoUrl` means the gym has no logo; don't ask for a known 404.
            guard gym.logoUrl != nil, let store else { return }
            let slug = gym.slug
            loaded = await store.logo(for: slug).map { (slug, $0) }
        }
    }

    /// The mockup's rule: the first letter of the first two words that start with a letter,
    /// skipping "the", "of" and "and" — "The Peak of Fremont" is "PF".
    nonisolated static func initials(for name: String) -> String {
        let skipped: Set<String> = ["the", "of", "and"]
        return name.split(separator: " ")
            .filter { word in
                word.first.map { $0.isASCII && $0.isLetter } == true
                    && !skipped.contains(word.lowercased())
            }
            .prefix(2)
            .compactMap { $0.first?.uppercased() }
            .joined()
    }
}

/// What `LogoImage` draws for a given image, split out so snapshots needn't load anything.
struct LogoChip: View {
    let name: String
    let image: UIImage?
    let size: CGFloat
    let tint: Color?

    var body: some View {
        RoundedRectangle(cornerRadius: (size * 0.3).rounded(), style: .continuous)
            .fill(background)
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .renderingMode(tint == nil ? .original : .template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(foreground)
                        .padding(size * 0.12)
                } else {
                    Text(LogoImage.initials(for: name))
                        // The mockup sizes initials at about 0.31 of the chip, never below 12pt.
                        .font(.system(size: max(12, (size * 0.31).rounded()), weight: .bold))
                        .foregroundStyle(foreground)
                }
            }
            // The gym's name always sits beside the chip; reading it twice adds nothing.
            .accessibilityHidden(true)
    }

    private var background: Color {
        tint.map { $0.opacity(0.12) } ?? Theme.surface
    }

    private var foreground: Color {
        tint ?? Theme.textSecondary
    }
}

#Preview("Logo chips") {
    let gym = Gym(
        slug: "dogpatch",
        name: "Dogpatch Boulders",
        brand: .touchstone,
        city: "San Francisco",
        latitude: 37.7567,
        longitude: -122.3903,
        logoUrl: nil,
        isMember: false,
        busyness: ResolvedBusyness(at: .now, isOpen: true, busyPct: 32, level: .quiet, source: .live)
    )
    return HStack(spacing: 16) {
        LogoImage(gym: gym, size: 36)
        LogoImage(gym: gym)
        LogoImage(gym: gym, size: 72)
        LogoImage(gym: gym, size: 52, tint: Theme.onBrandPrimaryIcon)
            .padding(8)
            .background(Theme.brandPrimary, in: RoundedRectangle(cornerRadius: 16))
    }
    .padding()
    .background(Theme.background)
}
