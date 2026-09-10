import SwiftUI

/// Crowd level, always word first and number second. One component, four placements
/// from the mockup; a nil percentage reads "Closed".
struct BusynessBadge: View {
    enum Variant {
        /// Map card: 16pt word over "54% full".
        case mapCard
        /// Rankings and gym rows: 13pt word over "54%".
        case row
        /// Best-pick card: dot, 17pt word and "54% full" in a row, on-dark palette.
        case onDark
        /// Pin chip: 11pt word beside "54%".
        case chip
    }

    let percent: Int?
    var variant: Variant = .row

    private var level: BusynessLevel? { percent.map(BusynessLevel.init(percent:)) }

    var body: some View {
        switch variant {
        case .mapCard:
            VStack(alignment: .trailing, spacing: 2) {
                word(font: .system(size: 16, weight: .bold))
                detail(suffix: "% full", font: Typography.footnote)
            }
        case .row:
            VStack(alignment: .trailing, spacing: 2) {
                word(font: .system(size: 13, weight: .bold))
                detail(suffix: "%", font: .system(size: 11))
            }
        case .onDark:
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 10, height: 10)
                word(font: Typography.headline)
                detail(suffix: "% full", font: Typography.caption)
            }
        case .chip:
            HStack(alignment: .firstTextBaseline) {
                word(font: .system(size: 11, weight: .bold))
                Spacer(minLength: 4)
                detail(suffix: "%", font: Typography.micro)
            }
        }
    }

    private var onDark: Bool { variant == .onDark }

    private var color: Color {
        guard let level else { return onDark ? Theme.onBrandPrimaryMuted : Theme.textTertiary }
        return Theme.Busyness.color(for: level, onDark: onDark)
    }

    private func word(font: Font) -> some View {
        Text(level?.label ?? "Closed")
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    @ViewBuilder
    private func detail(suffix: String, font: Font) -> some View {
        if let percent {
            Text("\(percent)\(suffix)")
                .font(font)
                .monospacedDigit()
                .foregroundStyle(onDark ? Theme.onBrandPrimaryMuted : Theme.textTertiary)
        }
    }
}

/// The small clay "Member" tag next to a gym name.
struct MemberBadge: View {
    var onDark = false
    var compact = false

    var body: some View {
        Text("Member")
            .font(compact ? Typography.micro : Typography.badge)
            .foregroundStyle(onDark ? Theme.clayOnDark : Theme.clayText)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, 2)
            .background(
                onDark ? Theme.clayOnDark.opacity(0.18) : Theme.clayBadgeTint,
                in: RoundedRectangle(cornerRadius: compact ? 5 : Radius.badge, style: .continuous)
            )
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 24) {
            BusynessBadge(percent: 22, variant: .mapCard)
            BusynessBadge(percent: 54, variant: .row)
            BusynessBadge(percent: 88, variant: .row)
            BusynessBadge(percent: nil, variant: .row)
        }
        BusynessBadge(percent: 54, variant: .chip).frame(width: 62)
        HStack {
            BusynessBadge(percent: 31, variant: .onDark)
            MemberBadge(onDark: true)
        }
        .padding()
        .background(Theme.brandPrimary, in: RoundedRectangle(cornerRadius: Radius.card))
        HStack { MemberBadge(); MemberBadge(compact: true) }
    }
    .padding()
    .background(Theme.background)
}
