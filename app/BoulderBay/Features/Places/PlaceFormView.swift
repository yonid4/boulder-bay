import SwiftUI

/// The add / edit place form: kind, label, address search, and the save button. It has no
/// header or scroll view of its own, so the onboarding step and the places sheet can each
/// frame it their way.
struct PlaceFormView: View {
    @Bindable var model: PlaceFormModel
    var submitLabel = "Save place"
    /// Called with the saved place once the API has accepted it.
    var onSaved: (SavedLocation) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Kind") { kindPicker }
            section("Label") {
                TextField("Label", text: $model.label)
                    .textInputAutocapitalization(.words)
                    .placeField()
            }
            section("Address") {
                addressField
                if !model.suggestions.isEmpty {
                    suggestionList
                }
            }

            if let message = model.errorMessage {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.danger)
            }

            Button {
                Task {
                    if let saved = await model.save() { onSaved(saved) }
                }
            } label: {
                if model.isSaving {
                    ProgressView().tint(Theme.onBrandPrimary)
                } else {
                    Text(submitLabel)
                }
            }
            .buttonStyle(.primary)
            .disabled(!model.canSave)
        }
        .task(id: model.query) {
            await model.searchSuggestions()
        }
    }

    private func section(
        _ title: String, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
            content()
        }
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(model.availableKinds, id: \.self) { kind in
                let isSelected = kind == model.kind
                Button {
                    model.kind = kind
                } label: {
                    Label(kind.title, systemImage: kind.symbolName)
                }
                .buttonStyle(KindChipStyle(isSelected: isSelected))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var addressField: some View {
        HStack(spacing: 8) {
            Image(systemName: model.selectedAddress == nil ? "magnifyingglass" : "mappin.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    model.selectedAddress == nil ? Theme.textTertiary : Theme.brandPrimary
                )
            TextField("Search for an address", text: $model.query)
                .textContentType(.fullStreetAddress)
                .autocorrectionDisabled()
            if model.isResolving {
                ProgressView()
            } else if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Theme.borderSolid, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear address")
            }
        }
        .placeField()
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(model.suggestions) { suggestion in
                Button {
                    Task { await model.select(suggestion) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isResolving)

                if suggestion != model.suggestions.last {
                    Rectangle()
                        .fill(Theme.textPrimary.opacity(0.06))
                        .frame(height: 1)
                }
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.06), radius: 10, y: 6)
    }
}

/// A kind pill: forest green when chosen, a white capsule on a soft shadow otherwise.
private struct KindChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? Theme.onBrandPrimary : Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background {
                Capsule()
                    .fill(isSelected ? Theme.brandPrimary : Theme.card)
                    .shadow(color: Theme.shadow.opacity(isSelected ? 0 : 0.1), radius: 2, y: 1)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The white, hairline-bordered field the sign-in screen uses.
private struct PlaceFieldModifier: ViewModifier {
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
    func placeField() -> some View {
        modifier(PlaceFieldModifier())
    }
}
