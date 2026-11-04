import SwiftUI

extension EnvironmentValues {
    /// Opens the places sheet. `AppShell` sets it for its screens and presents the sheet, so
    /// anything inside the shell can open it; without it (previews, snapshots) it's nil.
    @Entry var showPlaces: (@MainActor @Sendable () -> Void)? = nil
}

/// The places sheet: every saved place with its kind and default tag. Tap a row to edit it,
/// swipe to delete, or add a new one. Opened from the side menu's "Your places" row.
struct PlacesView: View {
    @State private var viewModel: PlacesViewModel
    /// The open add / edit form. Built on tap, so each one starts from the current list.
    @State private var form: PlaceFormModel?
    @Environment(\.dismiss) private var dismiss

    init(apiClient: APIClient, appModel: AppModel) {
        self.init(viewModel: PlacesViewModel(apiClient: apiClient, appModel: appModel))
    }

    /// For snapshots and previews.
    init(viewModel: PlacesViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlacesSheetHeader(title: "Your places") { dismiss() }

            if let message = viewModel.errorMessage {
                errorLine(message)
            }

            List {
                ForEach(viewModel.locations) { location in
                    row(for: location)
                        .listRowBackground(Theme.card)
                        .listRowSeparatorTint(Theme.divider)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // No `.destructive` role: it animates the row away straight off,
                            // and this delete can still fail.
                            if viewModel.canDelete {
                                Button("Delete", systemImage: "trash") {
                                    Task { await viewModel.delete(location) }
                                }
                                .tint(Theme.danger)
                            }
                        }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 12, for: .scrollContent)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Add a place") {
                form = viewModel.addForm(search: MapKitAddressSearch())
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Theme.background)
        .sheet(item: $form) { form in
            PlaceEditorView(model: form)
        }
    }

    private func errorLine(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
            if viewModel.needsReload {
                Button("Try again") {
                    Task { await viewModel.reload() }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.brandPrimary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func row(for location: SavedLocation) -> some View {
        HStack(spacing: 12) {
            Button {
                form = viewModel.editForm(for: location, search: MapKitAddressSearch())
            } label: {
                rowLabel(for: location)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits this place")

            trailing(for: location)
        }
        .padding(.vertical, 4)
    }

    private func rowLabel(for location: SavedLocation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: location.kind.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(location.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let address = location.address {
                    // "Make default" narrows the row, and an ordinary street and city fill it.
                    Text(address)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    /// What sits at the row's end: the spinner while a write runs, else the tag or the action.
    @ViewBuilder
    private func trailing(for location: SavedLocation) -> some View {
        if viewModel.pendingLocationID == location.id {
            ProgressView()
        } else if viewModel.canMakeDefault(location) {
            Button("Make default") {
                Task { await viewModel.makeDefault(location) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.brandPrimary)
            .fixedSize()
            .disabled(viewModel.pendingLocationID != nil)
        } else {
            Text("Default")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.clayText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.clayBadgeTint, in: Capsule())
                .fixedSize()
        }
    }
}

/// The add / edit form as its own sheet over the list: a header, then `PlaceFormView`
/// scrolling above the keyboard. Saving closes it.
struct PlaceEditorView: View {
    @State private var model: PlaceFormModel
    @Environment(\.dismiss) private var dismiss

    init(model: PlaceFormModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlacesSheetHeader(title: model.isEditing ? "Edit place" : "Add a place") { dismiss() }
                .disabled(model.isSaving)

            ScrollViewReader { proxy in
                ScrollView {
                    PlaceFormView(
                        model: model,
                        submitLabel: model.isEditing ? "Save place" : "Add place",
                        onSaved: { _ in dismiss() }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                // Results open below the field, mostly behind the keyboard. Once per search,
                // not per keystroke, so it doesn't fight someone who has scrolled back up.
                .onChange(of: model.suggestions.isEmpty) { _, isEmpty in
                    guard !isEmpty else { return }
                    withAnimation {
                        proxy.scrollTo(PlaceFormView.addressSectionID, anchor: .top)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 24, for: .scrollContent)
        }
        .background(Theme.background)
        .interactiveDismissDisabled(model.isSaving)
    }
}

/// The title and close button at the top of the places sheet and its form.
private struct PlacesSheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.top, 14)
    }
}

extension PlaceFormModel: Identifiable {}
