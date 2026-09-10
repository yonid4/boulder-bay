import MapKit
import SwiftUI

/// Full-screen MapKit map of the sixteen gyms, with the controls floating over it and
/// the selected gym's card sliding up from the bottom.
struct MapView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppShellViewModel.self) private var shell
    @State private var model: MapViewModel?

    var body: some View {
        ZStack {
            if let model {
                content(model)
            } else {
                Theme.surface.ignoresSafeArea()
            }
        }
        .task {
            // One task, created with the model: a `.task(id:)` keyed on the model's
            // presence would cancel the load it had just started.
            if model == nil {
                model = MapViewModel(
                    gyms: container.gyms, rankings: container.rankings,
                    memberships: container.memberships, locations: container.locations
                )
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(_ model: MapViewModel) -> some View {
        @Bindable var model = model
        GeometryReader { proxy in
            Map(position: $model.camera, interactionModes: [.pan, .zoom]) {
                if let location = model.location {
                    Annotation("", coordinate: location.coordinate, anchor: .center) {
                        LocationDot()
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(model.visiblePins) { pin in
                    Annotation("", coordinate: pin.coordinate, anchor: .bottom) {
                        GymAnnotation(
                            pin: pin,
                            isSelected: model.selectedSlug == pin.id,
                            showChip: model.showChips
                        ) {
                            model.select(pin.id)
                        }
                        // Anchor the dot, not the chip, on the coordinate.
                        .offset(y: 9)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls {}
            .onMapCameraChange(frequency: .continuous) { context in
                model.cameraChanged(region: context.region)
            }
            .onTapGesture {
                if model.isTimeOpen { model.closeTime() } else { model.select(nil) }
            }
            .onAppear { model.viewSize = proxy.size }
            .onChange(of: proxy.size) { _, size in model.viewSize = size }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            MapControlsView(model: model) { shell.openMenu() }
                .padding(.horizontal, Spacing.screen)
                .padding(.top, Spacing.topChrome)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            if let pin = model.selectedPin {
                GymBusynessCard(pin: pin, effectiveHour: container.rankings.effectiveHour) {
                    shell.openDetail(slug: pin.id)
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: model.selectedSlug)
        .overlay {
            if model.isLoading {
                LoadingView(text: "Loading gyms…").opacity(0.9)
            }
        }
    }
}

#Preview {
    AppShellView().environment(AppContainer.preview())
}
