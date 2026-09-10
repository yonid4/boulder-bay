import SwiftUI

/// The create form: a label, a place search, the chosen place, and Save.
struct LocationEditorView: View {
    @Bindable var model: LocationsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Label")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textTertiary)
                TextField("Home", text: $model.label)
                    .textFieldStyle(AuthTextFieldStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Where")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textTertiary)
                if let place = model.place {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.title)
                                .font(Typography.rowTitle)
                                .foregroundStyle(Theme.textPrimary)
                            Text(place.address)
                                .font(Typography.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Button("Change") { model.clearPlace() }
                            .buttonStyle(PillButtonStyle(kind: .added))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .strokeBorder(Theme.textPrimary.opacity(0.08))
                    )
                } else {
                    LocationSearchField(search: model.search) { completion in
                        Task { await model.pick(completion) }
                    }
                }
            }

            if let message = model.errorMessage {
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.danger)
            }

            Button {
                Task { await model.save() }
            } label: {
                if model.isSaving {
                    ProgressView().tint(Theme.onBrandPrimary)
                } else {
                    Text("Save location")
                }
            }
            .buttonStyle(.primary)
            .disabled(!model.canSave)
            .opacity(model.canSave ? 1 : 0.5)
        }
    }
}
