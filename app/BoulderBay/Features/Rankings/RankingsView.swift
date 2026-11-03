import SwiftUI

/// Placeholder until the Rankings screen is built: the mockup's header and a note.
struct RankingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                MenuButton()
                Text("Rankings")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()
            Text("The best gym for you right now, and the rest in order, will show here.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
            Spacer()
        }
        .background(Theme.background)
    }
}

#Preview {
    RankingsView()
}
