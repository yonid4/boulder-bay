import SwiftUI

/// Placeholder until the Gyms screen is built: the mockup's header and a note.
struct GymsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                MenuButton()
                Text("Gyms")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()
            Text("Your gyms, and a search over all sixteen, will show here.")
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
    GymsView()
}
