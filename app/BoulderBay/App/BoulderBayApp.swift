import SwiftUI

@main
struct BoulderBayApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .task { await container.start() }
        }
    }
}
