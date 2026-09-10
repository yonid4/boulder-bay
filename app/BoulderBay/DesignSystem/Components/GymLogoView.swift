import SwiftUI

/// A gym's mark in a rounded square chip, fetched from `logoURL`; falls back to the
/// two-letter monogram on stone while loading, on failure, or when nothing serves the
/// logo yet. `.onDark` is for the forest-green best-pick card: the mark renders as a
/// template in a light tint, since a black silhouette would vanish against the green.
struct GymLogoView: View {
    enum Style {
        case light, onDark
    }

    let name: String
    let logoURL: URL?
    var size: CGFloat = 48
    var style: Style = .light

    init(gym: Gym, size: CGFloat = 48, style: Style = .light) {
        self.init(name: gym.name, logoURL: gym.logoURL, size: size, style: style)
    }

    init(name: String, logoURL: URL?, size: CGFloat = 48, style: Style = .light) {
        self.name = name
        self.logoURL = logoURL
        self.size = size
        self.style = style
    }

    var body: some View {
        ZStack {
            if let logoURL {
                AsyncImage(url: logoURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        mark(image)
                    } else {
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .background(chipColor, in: RoundedRectangle(cornerRadius: Radius.logo(forSize: size), style: .continuous))
        .accessibilityLabel("\(name) logo")
    }

    @ViewBuilder
    private func mark(_ image: Image) -> some View {
        switch style {
        case .light:
            image.resizable().scaledToFit()
        case .onDark:
            image.resizable().renderingMode(.template).scaledToFit()
                .foregroundStyle(Theme.onBrandPrimaryIcon)
        }
    }

    private var monogram: some View {
        Text(name.initials)
            .font(.system(size: (size * 0.31).rounded(), weight: .bold))
            .kerning(0.2)
            .foregroundStyle(style == .light ? Theme.textSecondary : Theme.onBrandPrimaryIcon)
    }

    private var chipColor: Color {
        style == .light ? Theme.surface : Theme.onBrandPrimary.opacity(0.12)
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            GymLogoView(name: "Great Western Power Company", logoURL: nil, size: 72)
            GymLogoView(name: "The Peak of Fremont", logoURL: nil, size: 48)
            GymLogoView(name: "Mosaic Boulders", logoURL: nil, size: 36)
        }
        HStack(spacing: 12) {
            GymLogoView(name: "Movement Belmont", logoURL: nil, size: 52, style: .onDark)
        }
        .padding()
        .background(Theme.brandPrimary, in: RoundedRectangle(cornerRadius: Radius.card))
    }
    .padding()
    .background(Theme.background)
}
