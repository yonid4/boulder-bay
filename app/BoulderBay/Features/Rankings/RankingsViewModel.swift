import Foundation

/// Fetches the rankings for `AppModel`'s selected place and hour.
@MainActor
@Observable
final class RankingsViewModel {
    /// What a loaded list is an answer for.
    struct Selection: Equatable {
        let locationID: UUID?
        let hour: Int
    }

    enum Phase: Equatable {
        case loading
        case failed(String)
        /// `refreshError` is set when a refresh failed and the list is the previous answer.
        case loaded(Rankings, refreshError: String?)
    }

    let appModel: AppModel

    private var rankings: Rankings?
    private var loadedSelection: Selection?
    private var errorMessage: String?
    /// The one load in flight, and what it is fetching.
    private var inFlight: (selection: Selection, task: Task<Void, Never>)?

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var selection: Selection {
        Selection(locationID: appModel.selectedLocationID, hour: appModel.selectedHour)
    }

    /// A list for another place or hour never shows under this one's header.
    var phase: Phase {
        if let rankings, loadedSelection == selection {
            return .loaded(rankings, refreshError: errorMessage)
        }
        if let errorMessage { return .failed(errorMessage) }
        return .loading
    }

    /// For the screen appearing or the selection changing. The screen's `.task` runs again when a
    /// pushed screen pops, and that mustn't refetch.
    func loadIfNeeded() async {
        guard loadedSelection != selection else { return }
        await load()
    }

    /// Fetches the current selection. A load already fetching it is joined; one fetching another
    /// is dropped. The load is owned here, so a pull to refresh that SwiftUI cancels when the view
    /// redraws doesn't fail it.
    func load() async {
        let selection = selection
        if let inFlight {
            guard inFlight.selection != selection else { return await inFlight.task.value }
            inFlight.task.cancel()
        }
        if loadedSelection != selection { errorMessage = nil }
        let task = Task { await fetch(selection) }
        inFlight = (selection, task)
        await task.value
    }

    private func fetch(_ selection: Selection) async {
        do {
            let rankings = try await appModel.rankingsForSelection()
            guard !Task.isCancelled else { return }
            inFlight = nil
            self.rankings = rankings
            // A deleted place falls back to another, so the answer says which place it's for.
            loadedSelection = Selection(locationID: rankings.location.id, hour: selection.hour)
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            inFlight = nil
            errorMessage = APIError.message(for: error)
        }
    }
}
