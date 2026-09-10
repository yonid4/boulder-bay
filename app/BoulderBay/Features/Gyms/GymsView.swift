import SwiftUI

/// The membership screen: search to add gyms, and the list of the ones you belong to.
struct GymsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppShellViewModel.self) private var shell
    @State private var model: GymsViewModel?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let model {
                content(model)
            }
        }
        .onAppear {
            if model == nil {
                model = GymsViewModel(
                    gyms: container.gyms, memberships: container.memberships, rankings: container.rankings
                )
            }
        }
        .task(id: model == nil) {
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(_ model: GymsViewModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ScreenHeader(title: "Gyms") { shell.openMenu() }
                .padding(.horizontal, Spacing.header)
                .padding(.top, Spacing.topChrome + 4)

            SearchField(text: $model.query, placeholder: "Search gyms to add")
                .padding(.horizontal, Spacing.screen)
                .padding(.top, Spacing.stack)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.hasQuery {
                        section(title: "Results") {
                            if model.noResults {
                                Text("No gyms match \u{201C}\(model.trimmedQuery)\u{201D}")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(24)
                            } else {
                                GymListCard {
                                    ForEach(model.results) { gym in
                                        GymRow(
                                            gym: gym,
                                            trailing: .add(isMember: model.isMember(gym)),
                                            onOpen: { shell.openDetail(slug: gym.slug) },
                                            onToggle: { Task { await model.toggle(gym) } }
                                        )
                                    }
                                }
                            }
                        }
                    }

                    section(title: "Your gyms", trailing: model.memberCountLabel) {
                        if let message = model.errorMessage {
                            Text(message)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.danger)
                                .padding(.horizontal, 4)
                        }
                        if model.memberGyms.isEmpty {
                            EmptyStateView(
                                message: "No gyms yet. Search above to add the gyms you belong to — they get priority on the map and a boost in Rankings."
                            )
                        } else {
                            GymListCard {
                                ForEach(model.memberGyms) { gym in
                                    GymRow(
                                        gym: gym,
                                        trailing: .remove,
                                        onOpen: { shell.openDetail(slug: gym.slug) },
                                        onToggle: { Task { await model.toggle(gym) } }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.top, 20)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .ignoresSafeArea(edges: .top)
        .animation(.easeOut(duration: 0.18), value: model.memberGyms.map(\.slug))
        .animation(.easeOut(duration: 0.18), value: model.hasQuery)
    }

    private func section(title: String, trailing: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Typography.caption)
                Spacer()
                if let trailing { Text(trailing).font(Typography.footnote) }
            }
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 4)
            content()
        }
    }
}

#Preview {
    struct Host: View {
        @State private var shell: AppShellViewModel = {
            let shell = AppShellViewModel()
            shell.select(.gyms)
            return shell
        }()
        var body: some View { GymsView().environment(shell) }
    }
    return Host().environment(AppContainer.preview())
}
