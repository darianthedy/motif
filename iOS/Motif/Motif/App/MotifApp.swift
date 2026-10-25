import SwiftUI

@main
struct MotifApp: App {
    @State private var app = AppState.live()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup { RootView().environment(app) }
            .onChange(of: phase) { _, next in
                if next == .active { Task { await app.store.refresh() } }
            }
    }
}
