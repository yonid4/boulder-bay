import MapKit
import SwiftUI

/// A gym's detail screen, pushed from `AppShell`'s stack with a `GymRoute`.
///
/// Unlike the root screens it keeps the navigation bar, for the back button.
struct GymDetailView: View {
    private let appModel: AppModel
    @State private var model: GymDetailViewModel

    init(slug: String, apiClient: APIClient, appModel: AppModel) {
        self.appModel = appModel
        _model = State(
            initialValue: GymDetailViewModel(slug: slug, apiClient: apiClient, appModel: appModel)
        )
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .tint(Theme.textPrimary)
            .task { await model.load() }
            // A poll tick landed new busyness for the current hour.
            .onChange(of: appModel.liveRefreshCount) {
                Task { await model.load() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .loaded(let detail):
            ScrollView {
                GymDetailContent(
                    detail: detail,
                    isMember: appModel.memberships.contains(detail.gym.slug),
                    isNow: appModel.isSelectedHourNow,
                    now: appModel.currentDate,
                    onOpenInMaps: { MKMapItem.forGym(detail.gym).openInMaps() }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await model.load() } }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.brandPrimary)
            }
            .padding(32)
        }
    }
}

extension MKMapItem {
    /// From the coordinates, since there is no stored map URL. Named so Maps shows the gym
    /// rather than a dropped pin.
    static func forGym(_ gym: Gym) -> MKMapItem {
        let item = if #available(iOS 26, *) {
            MKMapItem(
                location: CLLocation(latitude: gym.latitude, longitude: gym.longitude),
                address: nil
            )
        } else {
            MKMapItem(placemark: MKPlacemark(coordinate: gym.coordinate))
        }
        item.name = gym.name
        return item
    }
}
