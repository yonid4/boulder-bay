import SwiftUI

/// A themed spinner with a caption, for the resolving/loading gates.
struct LoadingView: View {
    var text = "Loading…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.brandPrimary)
            Text(text).font(Typography.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// A stone card with a centered message — "No gyms yet…" and failure states.
struct EmptyStateView: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PillButtonStyle(kind: .add))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.listCard, style: .continuous))
    }
}

/// The Gyms screen's search box: white, r14, magnifier, clear button when non-empty.
struct SearchField: View {
    @Binding var text: String
    var placeholder = "Search"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
            TextField(placeholder, text: $text)
                .font(Typography.body)
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Theme.card)
                        .frame(width: 20, height: 20)
                        .background(Theme.borderSolid, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.06))
        )
        .shadow(color: Theme.shadow.opacity(0.06), radius: 1, y: 1)
    }
}

/// The 52pt white text field from the auth screens.
struct AuthTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(Typography.body)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08))
            )
    }
}

#Preview {
    struct Demo: View {
        @State private var query = "Bench"
        var body: some View {
            VStack(spacing: 20) {
                SearchField(text: $query, placeholder: "Search gyms to add")
                TextField("Email", text: .constant("")).textFieldStyle(AuthTextFieldStyle())
                EmptyStateView(message: "No gyms yet. Search above to add the gyms you belong to — they get priority on the map and a boost in Rankings.")
                EmptyStateView(message: "Couldn't load gyms.", actionTitle: "Retry") {}
                LoadingView(text: "Loading gyms…").frame(height: 120)
            }
            .padding()
            .background(Theme.background)
        }
    }
    return Demo()
}
