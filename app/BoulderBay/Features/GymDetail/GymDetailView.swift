import SwiftUI

/// The shared push destination from Map, Rankings and Gyms: logo and name, the
/// busyness card with today's forecast, address / hours / rates, and the links.
struct GymDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppShellViewModel.self) private var shell
    @State private var model: GymDetailViewModel?

    let slug: String

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let model {
                content(model)
            }
        }
        .overlay(alignment: .topLeading) {
            BackButton { shell.pop() }
                .padding(.leading, 12)
                .padding(.top, 56)
                .ignoresSafeArea(edges: .top)
        }
        .onAppear {
            if model == nil {
                model = GymDetailViewModel(
                    slug: slug,
                    service: GymDetailService(api: container.api),
                    rankings: container.rankings,
                    memberships: container.memberships,
                    locations: container.locations
                )
            }
        }
        .task(id: model == nil) {
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(_ model: GymDetailViewModel) -> some View {
        switch model.state {
        case .loading:
            LoadingView(text: "Loading…")
        case .failed(let message):
            EmptyStateView(message: message, actionTitle: "Retry") { Task { await model.load() } }
                .padding(.horizontal, Spacing.screen)
        case .loaded:
            if let gym = model.gym {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GymHeaderView(gym: gym, isMember: model.isMember)
                        BusynessCard(model: model)
                        InfoRows(model: model)
                        GymLinksView(gym: gym)
                    }
                    .padding(.horizontal, Spacing.screen)
                    .padding(.top, 110)
                    .padding(.bottom, 48)
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
            }
        }
    }
}

#Preview {
    NavigationStack {
        GymDetailView(slug: "mv-belmont")
    }
    .environment(AppShellViewModel())
    .environment(AppContainer.preview())
}
