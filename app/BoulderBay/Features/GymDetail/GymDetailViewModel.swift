import Foundation
import Observation

/// Loads one gym's detail for the hour the Map and Rankings are on, so all of them agree.
@MainActor
@Observable
final class GymDetailViewModel {
    enum State: Equatable {
        case loading
        case loaded(GymDetail)
        case failed(String)
    }

    private(set) var state: State = .loading

    private let slug: String
    private let apiClient: APIClient
    private let appModel: AppModel
    /// Bumped by each `load()`, so only the newest one may publish.
    private var latestLoad = 0

    init(slug: String, apiClient: APIClient, appModel: AppModel) {
        self.slug = slug
        self.apiClient = apiClient
        self.appModel = appModel
    }

    /// Fetches the detail. A refresh keeps what's on screen: no spinner while it runs, and if it
    /// fails the last good detail stays until the next one succeeds.
    func load() async {
        latestLoad += 1
        let thisLoad = latestLoad
        if case .loaded = state {} else { state = .loading }

        do {
            let detail = try await apiClient.gymDetail(
                slug: slug, at: appModel.date(forHour: appModel.selectedHour)
            )
            guard thisLoad == latestLoad else { return }
            state = .loaded(detail)
        } catch {
            // Cancelled means the screen went away; `.task` loads again if it comes back.
            guard thisLoad == latestLoad, !Task.isCancelled else { return }
            if case .loaded = state { return }
            state = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: any Error) -> String {
        if case APIError.badStatus(404) = error { return "This gym is no longer available." }
        return APIError.message(for: error)
    }
}
