import SwiftUI

/// Hosts the two auth screens and the email-confirmation interstitial, sharing one
/// view model so the typed email survives switching modes.
struct AuthFlowView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: AuthenticationViewModel?

    var body: some View {
        // ZStack rather than Group: a Group that renders nothing never gets onAppear,
        // so the model would never be created.
        ZStack {
            Theme.background.ignoresSafeArea()
            if let model {
                if let email = model.awaitingConfirmationEmail {
                    ConfirmEmailView(email: email) { await model.returnToSignIn() }
                } else if model.mode == .signUp {
                    SignUpView(model: model)
                } else {
                    LoginView(model: model)
                }
            }
        }
        .onAppear {
            if model == nil { model = AuthenticationViewModel(auth: container.auth) }
        }
    }
}

struct LoginView: View {
    @Bindable var model: AuthenticationViewModel

    var body: some View {
        AuthScreen(model: model) {
            TextField("Email", text: $model.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(AuthTextFieldStyle())
            SecureField("Password", text: $model.password)
                .textContentType(.password)
                .textFieldStyle(AuthTextFieldStyle())
                .submitLabel(.go)
                .onSubmit { Task { await model.submit() } }
        }
    }
}

/// The shared auth layout: clay app tile, title, subtitle, fields, primary CTA, error
/// line, and the mode switch pinned to the bottom.
struct AuthScreen<Fields: View>: View {
    @Bindable var model: AuthenticationViewModel
    @ViewBuilder let fields: () -> Fields

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                AppIconTile()
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.title)
                        .font(.system(size: 28, weight: .bold))
                        .tightTracking()
                        .foregroundStyle(Theme.textPrimary)
                    Text(model.subtitle)
                        .font(Typography.rowBody)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(3)
                }
            }

            VStack(spacing: 10) {
                fields()
                Button {
                    Task { await model.submit() }
                } label: {
                    if model.isBusy {
                        ProgressView().tint(Theme.onBrandPrimary)
                    } else {
                        Text(model.submitTitle)
                    }
                }
                .buttonStyle(.primary)
                .disabled(model.isBusy)
                .padding(.top, 6)

                if let message = model.errorMessage {
                    Text(message)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 0)

            Button(model.switchTitle) {
                withAnimation(.easeOut(duration: 0.15)) { model.toggleMode() }
            }
            .font(.system(size: 14))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.top, 72)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
        .animation(.easeOut(duration: 0.15), value: model.errorMessage)
    }
}

/// The 56pt clay tile with the chalk dot — the app icon, as the mockup draws it.
struct AppIconTile: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(Theme.clay)
            Circle().fill(Theme.background).frame(width: size * 0.25, height: size * 0.25)
            Circle().stroke(Theme.background.opacity(0.28), lineWidth: size * 0.09)
                .frame(width: size * 0.34, height: size * 0.34)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Shown after sign-up when the Supabase project requires the email link first.
struct ConfirmEmailView: View {
    let email: String
    let onBack: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                AppIconTile()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check your email")
                        .font(.system(size: 28, weight: .bold))
                        .tightTracking()
                        .foregroundStyle(Theme.textPrimary)
                    Text("We sent a confirmation link to \(email). Tap it, then come back and sign in.")
                        .font(Typography.rowBody)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(3)
                }
            }
            Spacer(minLength: 0)
            Button("Back to sign in") { Task { await onBack() } }
                .buttonStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 72)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
    }
}

#Preview("Sign in") {
    LoginView(model: AuthenticationViewModel(auth: MockAuthService()))
}

#Preview("Confirm email") {
    ConfirmEmailView(email: "alex.chen@example.com") {}
}
