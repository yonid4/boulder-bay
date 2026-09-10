import SwiftUI

/// "Best gym right now": the green best-pick card and seven runners-up, with the same
/// time chip and scrubber as the map.
struct RankingsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppShellViewModel.self) private var shell
    @State private var model: RankingsViewModel?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let model {
                content(model)
            }
        }
        .task {
            if model == nil {
                model = RankingsViewModel(
                    gyms: container.gyms, rankings: container.rankings,
                    memberships: container.memberships, locations: container.locations
                )
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(_ model: RankingsViewModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(spacing: Spacing.stack) {
                ScreenHeader(title: "Rankings", subtitle: model.subtitle, onMenu: { shell.openMenu() }) {
                    if model.plannableHours != nil {
                        TimeChip(label: model.timeChipLabel, isExpanded: model.isTimeOpen, glass: false) {
                            model.toggleTime()
                        }
                    }
                }
                if model.isTimeOpen, let range = model.plannableHours {
                    TimeScrubberView(plannedHour: $model.plannedHour, range: range, glass: false)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, Spacing.header)
            .padding(.top, Spacing.topChrome + 4)
            .padding(.bottom, Spacing.screen)
            .animation(.easeOut(duration: 0.18), value: model.isTimeOpen)

            if model.isLoading {
                LoadingView(text: "Scoring gyms…")
            } else if let message = model.errorMessage {
                EmptyStateView(message: message, actionTitle: "Retry") { Task { await model.retry() } }
                    .padding(.horizontal, Spacing.screen)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if let best = model.best {
                            BestPickCard(ranked: best, label: model.bestPickLabel, why: model.whyLine(for: best)) {
                                shell.openDetail(slug: best.id)
                            }
                            .padding(.bottom, 8)
                        }
                        ForEach(model.rest) { ranked in
                            RankingRow(ranked: ranked) { shell.openDetail(slug: ranked.id) }
                        }
                    }
                    .padding(.horizontal, Spacing.screen)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onTapGesture { if model.isTimeOpen { model.closeTime() } }
    }
}

#Preview {
    struct Host: View {
        @State private var shell: AppShellViewModel = {
            let shell = AppShellViewModel()
            shell.select(.rankings)
            return shell
        }()
        var body: some View {
            RankingsView().environment(shell)
        }
    }
    return Host().environment(AppContainer.preview())
}
