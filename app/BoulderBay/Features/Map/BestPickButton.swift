import SwiftUI

/// The map's "Best right now" / "Best at 7 PM" pill: the mockup's green button with its dot, which
/// a spinner replaces while the rankings load.
struct BestPickButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.onBrandPrimary)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(Theme.Busyness.quietOnDark)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onBrandPrimary)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(height: 34)
            .background {
                Capsule(style: .circular)
                    .fill(Theme.brandPrimary)
                    .shadow(color: Theme.brandPrimary.opacity(0.25), radius: 24, y: 8)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
