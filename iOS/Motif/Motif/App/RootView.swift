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
            Tab("Puzzles", systemImage: "puzzlepiece", value: .puzzles) {
                NavigationStack(path: $app.puzzlesPath) {
                    PuzzlesHomeView().libraryBanners()
                        .navigationDestination(for: PuzzleRoute.self) { route in
                            Group {
                                switch route {
                                case .collection(let id): CollectionView(collectionId: id)
                                case .puzzles(let id): PuzzleListView(collectionId: id)
                                case .puzzle(_, let id): PuzzleDetailView(puzzleId: id)
                                }
                            }.libraryBanners()
                        }
                }
            }
            Tab("Games", systemImage: "checkerboard.rectangle", value: .games) {
                NavigationStack(path: $app.gamesPath) {
                    GamesHomeView().libraryBanners()
                        .navigationDestination(for: GamesRoute.self) { route in
                            Group {
                                switch route {
                                case .collection(let id): GameCollectionView(collectionId: id)
                                case .game(_, let id): GameView(gameId: id)
                                }
                            }.libraryBanners()
                        }
                }
            }
            Tab("Account", systemImage: "person.crop.circle", value: .account) {
                NavigationStack { AccountView().libraryBanners() }
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
