import Supabase
import SwiftUI

struct AuthenticationView: View {
    @Bindable var model: AuthenticationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                form
            }
            .padding(.horizontal, 28)
            .padding(.top, 96)
        }
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, 60, for: .scrollContent)
        .overlay {
            VStack {
                Spacer()
                Button(model.switchModeLabel) {
                    model.toggleMode()
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 16)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .background(Theme.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            appMark
                .padding(.bottom, 16)
            Text(model.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(model.subtitle)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var appMark: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.clay)
            .frame(width: 56, height: 56)
            .overlay {
                Circle()
                    .fill(Theme.background)
                    .frame(width: 14, height: 14)
            }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.mode == .signUp {
                TextField("Name", text: $model.displayName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .authField()
            }
            TextField("Email", text: $model.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .authField()
            SecureField("Password", text: $model.password)
                .textContentType(model.mode == .signIn ? .password : .newPassword)
                .authField()

            if let message = model.errorMessage {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.danger)
            } else if model.isAwaitingEmailConfirmation {
                Text("Check your email to confirm your account, then sign in.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                Task { await model.submit() }
            } label: {
                if model.isSubmitting {
                    ProgressView().tint(Theme.onBrandPrimary)
                } else {
                    Text(model.submitLabel)
                }
            }
            .buttonStyle(.primary)
            .disabled(!model.canSubmit)
            .padding(.top, 6)
        }
    }
}

private struct AuthFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 16))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            }
    }
}

private extension View {
    func authField() -> some View {
        modifier(AuthFieldModifier())
    }
}

#Preview {
    let supabase = SupabaseClient(
        supabaseURL: URL(string: "https://preview.supabase.co")!,
        supabaseKey: "preview-key"
    )
    AuthenticationView(model: AuthenticationViewModel(authService: AuthService(client: supabase)))
}
