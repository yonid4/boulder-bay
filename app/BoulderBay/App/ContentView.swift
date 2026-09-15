import SwiftUI

@MainActor
@Observable
final class GymListViewModel {
    enum State {
        case idle
        case loading
        case loaded([Gym])
        case failed(String)
    }

    private(set) var state: State = .idle
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await client.gyms())
        } catch {
            state = .failed(String(describing: error))
        }
    }
}

/// Placeholder root. Exists to prove the app ↔ backend wiring end to end;
/// the real Map / Rankings / Gyms drawer replaces it.
struct ContentView: View {
    @State private var model = GymListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .idle, .loading:
                    ProgressView("Loading gyms…")
                case .loaded(let gyms):
                    List(gyms) { gym in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gym.name).font(.headline)
                            Text("\(gym.city) · \(busynessDescription(for: gym))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .failed(let message):
                    ContentUnavailableView(
                        "Backend unreachable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(message)
                    )
                }
            }
            .navigationTitle("Boulder Bay")
        }
        .task { await model.load() }
    }

    private func busynessDescription(for gym: Gym) -> String {
        guard gym.busyness.isOpen else { return "Closed" }
        guard let busyPct = gym.busyness.busyPct, let level = gym.busyness.level else {
            return "Busyness unavailable"
        }

        return "\(level.rawValue.capitalized) (\(busyPct)%)"
    }
}

#Preview {
    ContentView()
}
