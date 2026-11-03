import SwiftUI

/// What the signed-in gate shows when `AppModel.bootstrap()` fails: the message, a retry, and
/// a way to sign out, since the shell and its menu aren't reachable from here.
struct AccountLoadFailedView: View {
    let message: String
    let onRetry: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
                Text("Couldn't load your account")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
            .multilineTextAlignment(.center)

            Button("Try again", action: onRetry)
                .buttonStyle(.primary)
                .padding(.top, 28)
            Spacer()
            Button("Sign out", action: onSignOut)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 16)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

#Preview {
    AccountLoadFailedView(
        message: "Couldn't reach the server. Check your connection.",
        onRetry: {},
        onSignOut: {}
    )
}
