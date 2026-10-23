import SwiftUI

@main
struct BoulderBayApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .environment(\.logoStore, container.logoStore)
        }
    }
}
