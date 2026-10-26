import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        @Bindable var app = app
        Group {
            switch app.root {
            case .unknown: Color(.systemBackground)
            case .signedOut: SignInView()
            case .waiting: loading
            case .library:
                #if DEBUG
                if app.launchRoute == "board" { NavigationStack { BoardSampleView() } } else { tabs }
                #else
                tabs
                #endif
            }
        }
        .tint(.motifAccentStrong)
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
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $app.showingAccount) { AccountView().environment(app) }
    }
    /// Signed in but no library yet: loading, a first launch offline, or a load that failed.
    @ViewBuilder private var loading: some View {
        Group {
            if app.store.loaded, !app.store.online {
                ContentUnavailableView("You’re Offline", systemImage: "wifi.slash",
                    description: Text("This device has no copy of your library yet. Connect once to download it."))
                    .accessibilityIdentifier("load-offline")
            } else if app.store.loaded, case .error(let message) = app.store.status {
                ContentUnavailableView {
                    Label("Couldn’t Load Your Library", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await app.store.open() } }
                        .buttonStyle(.glassProminent).accessibilityIdentifier("load-retry")
                    Button("Sign Out", role: .destructive) { Task { await app.signOut() } }
                        .accessibilityIdentifier("load-sign-out")
                }
            } else {
                ProgressView("Loading your library…").accessibilityIdentifier("load-progress")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = app.error { ErrorBanner(text: error) { app.error = nil } }
        }
    }
}
extension Color {
    /// Fills only (progress, bars): too light for text on white. Text and controls use the app tint, `motifAccentStrong`.
    static let motifAccent = Color(red: 0.43, green: 0.67, blue: 0.28)
    /// Deep enough for white text on it to stay readable.
    static let motifAccentStrong = Color(red: 0.24, green: 0.48, blue: 0.12)
}
