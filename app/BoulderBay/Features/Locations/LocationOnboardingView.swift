import SwiftUI

/// Required once after sign-up: the app shell isn't reachable until a location exists,
/// because rankings and travel times are measured from it.
struct LocationOnboardingView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: LocationsViewModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    AppIconTile()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Where do you climb from?")
                            .font(.system(size: 28, weight: .bold))
                            .tightTracking()
                            .foregroundStyle(Theme.textPrimary)
                        Text("Rankings and travel times start from here. Home, work — wherever you usually leave from.")
                            .font(Typography.rowBody)
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(3)
                    }
                }
                if let model {
                    LocationEditorView(model: model)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 72)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            if model == nil {
                model = LocationsViewModel(locations: container.locations, rankings: container.rankings)
            }
        }
    }
}

#Preview {
    LocationOnboardingView().environment(AppContainer.preview(fresh: true))
}
