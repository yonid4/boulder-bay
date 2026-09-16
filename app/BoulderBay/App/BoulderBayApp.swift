import SwiftUI

@main
struct BoulderBayApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            ContentView(container: container)
        }
    }
}
