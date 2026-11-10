import SwiftUI

@main
struct MotifApp: App {
    @State private var app = AppState.live()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup { RootView().environment(app).environment(\.motifReduceTransparency, Self.forcesReduceTransparency) }
            .onChange(of: phase) { _, next in
                if next == .active { Task { await app.store.refresh() } }
            }
    }
    /// The `reduce-transparency` capture fixture (D10): UI tests can't switch the system setting.
    private static var forcesReduceTransparency: Bool {
        #if DEBUG
        CaptureFixture.current.has("reduce-transparency")
        #else
        false
        #endif
    }
}
