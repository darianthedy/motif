import SwiftUI

@main
struct MotifApp: App {
    @State private var app = AppState.live()
    @Environment(\.scenePhase) private var phase
    init() {
        #if DEBUG
        // The UI tests launch with this: on iOS 27.1 the toolbar overflow menu keeps the app from
        // ever going idle, so each tap that opens or closes it waited out XCTest's 60 s idle timeout.
        if UserDefaults.standard.bool(forKey: "MotifUITestNoAnimations") { UIView.setAnimationsEnabled(false) }
        #endif
    }
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
