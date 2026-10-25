import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        @Bindable var app = app
        Group {
            switch app.root {
            case .unknown: Color(.systemBackground)
            case .signedOut: SignInView()
            case .waiting:
                if app.store.loaded {
                    ContentUnavailableView("Motif", systemImage: "square.grid.3x3", description: Text(waitingMessage))
                } else { ProgressView() }
            case .library:
                #if DEBUG
                if app.launchRoute == "board" { NavigationStack { BoardSampleView() } } else { tabs }
                #else
                tabs
                #endif
            }
        }
        .tint(.motifAccent)
        .task { await app.open() }
    }
    private var tabs: some View {
        @Bindable var app = app
        return TabView(selection: $app.tab) {
                    Tab("Puzzles", systemImage: "puzzlepiece", value: .puzzles) { NavigationStack(path: $app.puzzlesPath) { PuzzlesHomeView().navigationDestination(for: PuzzleRoute.self) { route in switch route { case .collection(let id): CollectionView(collectionId: id) } } } }
                    Tab("Games", systemImage: "checkerboard.rectangle", value: .games) { NavigationStack { GamesHomeView() } }
                    Tab("Account", systemImage: "person.crop.circle", value: .account) { NavigationStack { AccountView() } }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        OfflineBanner()
                        if let notice = app.notice { NoticeBanner(text: notice) { app.notice = nil } }
                    }
                }
    }
    private var waitingMessage: String {
        if !app.store.online { return "You're offline, and this device has no copy of your library yet. Connect once to download it." }
        if case .error(let message) = app.store.status { return "Could not load your library: \(message)" }
        return "Loading your library…"
    }
}
extension Color {
    static let motifAccent = Color(red: 0.43, green: 0.67, blue: 0.28)
}
