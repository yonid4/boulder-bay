import SwiftUI

/// The Gyms screen: the gyms you belong to, and a search over all of them to add more. Uses
/// `AppModel`'s gym list, loading it only if no other screen has.
struct GymsView: View {
    private let appModel: AppModel
    private let onOpenGym: (Gym) -> Void

    @State private var query = ""
    @State private var isSearching = false

    init(appModel: AppModel, onOpenGym: @escaping (Gym) -> Void) {
        self.appModel = appModel
        self.onOpenGym = onOpenGym
    }

    var body: some View {
        GymsContent(
            gyms: appModel.gyms,
            memberships: appModel.memberships,
            pendingMemberships: appModel.pendingMemberships,
            loadState: appModel.gymsState,
            query: $query,
            isSearching: $isSearching,
            membershipError: appModel.membershipError,
            onDismissError: { appModel.membershipError = nil },
            onRetry: { Task { await appModel.loadGyms() } },
            onOpenGym: onOpenGym,
            onToggle: { gym in
                Task { await appModel.toggleMembership(gymSlug: gym.slug) }
            }
        )
        .task { await appModel.loadGymsIfNeeded() }
        .onDisappear { appModel.membershipError = nil }
    }
}

#Preview {
    let apiClient = APIClient(accessToken: { "preview-token" })
    GymsView(appModel: AppModel(apiClient: apiClient), onOpenGym: { _ in })
}
