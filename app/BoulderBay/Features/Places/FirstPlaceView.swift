import SwiftUI

/// The onboarding step a signed-in account without places lands on: the place form, full
/// screen and with no way past it but saving. The save refreshes `AppModel`, and `RootView`'s
/// gate then moves on to the shell.
struct FirstPlaceView: View {
    @State private var model: PlaceFormModel
    private let onSignOut: () -> Void

    init(apiClient: APIClient, appModel: AppModel, onSignOut: @escaping () -> Void) {
        let model = PlaceFormModel(
            existing: appModel.locations,
            preferredKind: .home,
            search: MapKitAddressSearch()
        ) { body in
            try await Self.createFirstPlace(body, apiClient: apiClient, appModel: appModel)
        }
        self.init(model: model, onSignOut: onSignOut)
    }

    /// For snapshots and previews, with a model whose search and save are canned.
    init(model: PlaceFormModel, onSignOut: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onSignOut = onSignOut
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    header
                    PlaceFormView(model: model, submitLabel: "Add place")
                }
                .padding(.horizontal, 28)
                .padding(.top, 72)
            }
            // Results open below the field, mostly behind the keyboard. Once per search, not
            // per keystroke, so it doesn't fight someone who has scrolled back up.
            .onChange(of: model.suggestions.isEmpty) { _, isEmpty in
                guard !isEmpty else { return }
                withAnimation {
                    proxy.scrollTo(PlaceFormView.addressSectionID, anchor: .top)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, 60, for: .scrollContent)
        .overlay {
            // The only way out without a place: the wrong account, say.
            VStack {
                Spacer()
                Button("Sign out", action: onSignOut)
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.clay)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "mappin")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.background)
                }
                .accessibilityHidden(true)
                .padding(.bottom, 16)
            Text("Add a place")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Gyms are ranked by their distance from this place. You can add more places later.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Creates the place, which the server makes the default, then refreshes the places so
    /// the gate sees it. Errors from the create reach the form, `.conflict` included.
    ///
    /// Once the create has succeeded the place exists, so a failed refresh isn't rethrown:
    /// the form would offer a save that can only clash with it. A full `bootstrap()` runs
    /// instead, and if that fails too the gate shows its retry.
    static func createFirstPlace(
        _ body: CreateSavedLocation, apiClient: APIClient, appModel: AppModel
    ) async throws -> SavedLocation {
        let saved = try await apiClient.createLocation(body)
        do {
            try await appModel.reloadLocations()
        } catch {
            await appModel.bootstrap()
        }
        return saved
    }
}

#Preview {
    FirstPlaceView(
        model: PlaceFormModel(existing: [], search: MapKitAddressSearch()) { _ in
            throw CancellationError()
        },
        onSignOut: {}
    )
}
