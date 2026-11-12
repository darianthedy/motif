import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    /// The window's: compact collapses each split view to one stack, where the sidebar is a screen of its own.
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The window is taller than wide; with regular width that is the open-tall pose.
    @State private var taller = false
    var body: some View {
        @Bindable var app = app
        // Not a Group: a Group hands `.task` to each branch, so every root change
        // reopened the store and raced a second refresh against the first taps.
        ZStack {
            switch app.root {
            case .unknown: Color(.systemBackground)
            case .signedOut: SignInView()
            case .waiting: loading
            // A debug launch route opens before the tabs are built, so its selection and path are their first state.
            case .library where app.awaitingLaunchRoute: loading
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
        .onChange(of: app.root, initial: true) { _, root in if root == .library { app.openLaunchRoute() } }
    }
    /// Two tabs, each one `NavigationSplitView` (Duo plan decisions 4, 12, 16): the home list is the
    /// sidebar, the selected collection roots the detail column's stack. On compact width it
    /// collapses to one stack by itself; the selection, path and visibility live in `AppState`,
    /// so folding and unfolding keep them.
    private var tabs: some View {
        @Bindable var app = app
        return TabView(selection: $app.tab) {
            Tab("Puzzles", systemImage: "puzzlepiece", value: .puzzles) { puzzlesSplit }
            Tab("Games", systemImage: "checkerboard.rectangle", value: .games) { gamesSplit }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Decision 16: open tall, a selected collection shows the detail alone (sidebar on demand).
        .onGeometryChange(for: Bool.self) { $0.size.height > $0.size.width } action: { taller = $0 }
        .onChange(of: sizeClass == .regular && taller, initial: true) { _, tall in app.setOpenTall(tall) }
        .sheet(isPresented: $app.showingAccount) { AccountView().environment(app) }
        .sheet(isPresented: $app.importingPuzzles) { ImportView().environment(app) }
        .fullScreenCover(item: $app.session) { SessionView(scope: $0.scope).environment(app) }
        // A selected collection that is deleted (here or on another device) leaves the detail column.
        .onChange(of: app.store.library?.collections.map(\.id)) { _, ids in
            if let id = app.puzzlesCollection, let ids, !ids.contains(id) { app.openPuzzles([]) }
        }
        .onChange(of: app.store.library?.gameCollections.map(\.id)) { _, ids in
            if let id = app.gamesCollection, let ids, !ids.contains(id) { app.openGames([]) }
        }
    }
    private var puzzlesSplit: some View {
        @Bindable var app = app
        return NavigationSplitView(columnVisibility: $app.puzzlesColumns.visibility) {
            PuzzlesHomeView().libraryStatus().libraryMessages(shown: sizeClass == .compact)
                .navigationSplitViewColumnWidth(min: 300, ideal: Self.sidebarWidth, max: 360)
        } detail: {
            NavigationStack(path: $app.puzzlesPath) {
                Group {
                    if let id = app.puzzlesCollection, app.store.library?.collections.contains(where: { $0.id == id }) == true {
                        CollectionView(collectionId: id).id(id)
                    } else {
                        NoSelection(empty: app.store.library?.collections.isEmpty != false, systemImage: "puzzlepiece",
                                    openTall: app.puzzlesColumns.tall) {
                            EmptyState(title: "No Puzzles Yet", systemImage: "puzzlepiece",
                                       description: "Import a JSON collection to start solving.",
                                       action: .init(title: "Import Puzzles", identifier: "import-puzzles-empty-detail", disabled: !app.store.online) { app.importingPuzzles = true })
                        }
                    }
                }
                .libraryStatus().libraryMessages()
                .navigationDestination(for: PuzzleRoute.self) { route in
                    Group {
                        switch route {
                        case .collection(let id): CollectionView(collectionId: id)
                        case .puzzles(let id): PuzzleListView(collectionId: id)
                        case .puzzle(_, let id): PuzzleDetailView(puzzleId: id)
                        }
                    }.libraryStatus().libraryMessages()
                }
            }
        }
        .navigationSplitViewStyle(.automatic)
    }
    private var gamesSplit: some View {
        @Bindable var app = app
        return NavigationSplitView(columnVisibility: $app.gamesColumns.visibility) {
            GamesHomeView().libraryStatus().libraryMessages(shown: sizeClass == .compact)
                .navigationSplitViewColumnWidth(min: 300, ideal: Self.sidebarWidth, max: 360)
        } detail: {
            NavigationStack(path: $app.gamesPath) {
                Group {
                    if let id = app.gamesCollection, app.store.library?.gameCollections.contains(where: { $0.id == id }) == true {
                        GameCollectionView(collectionId: id).id(id)
                    } else {
                        NoSelection(empty: app.store.library?.gameCollections.isEmpty != false, systemImage: "checkerboard.rectangle",
                                    openTall: app.gamesColumns.tall) {
                            EmptyState(title: "No Games Yet", systemImage: "checkerboard.rectangle",
                                       description: "Make a collection, then add games as PGN or play them in on the board.",
                                       action: .init(title: "New Collection", identifier: "new-game-collection-empty-detail", disabled: !app.store.online) { app.creatingGameCollection = true })
                        }
                    }
                }
                .libraryStatus().libraryMessages()
                .navigationDestination(for: GamesRoute.self) { route in
                    Group {
                        switch route {
                        case .collection(let id): GameCollectionView(collectionId: id)
                        case .game(_, let id): GameView(gameId: id)
                        }
                    }.libraryStatus().libraryMessages()
                }
            }
        }
        .navigationSplitViewStyle(.automatic)
        .modifier(NewGameCollectionAlert())
    }
    /// The sidebar column on the open display (`shellGeom` in the Duo canvases: 340 pt on IL).
    private static let sidebarWidth: CGFloat = 340
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
        // The same centred column as sign-in (F22); errors use the one banner rule at the bottom.
        // The load error is already the screen, so the server status isn't repeated.
        .frame(maxWidth: SignInView.columnWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .libraryMessages(serverStatus: false)
    }
}
/// The detail column before a collection is picked. With no collections at all the sidebar
/// holds the home's empty state, so beside it this stays blank. Open tall the sidebar may be
/// off screen (the split view decides), so the detail repeats the empty state and its action.
private struct NoSelection<Empty: View>: View {
    let empty: Bool
    let systemImage: String
    let openTall: Bool
    @ViewBuilder let emptyState: () -> Empty
    var body: some View {
        if empty { if openTall { emptyState().readableWidth() } else { Color.clear } }
        else {
            ContentUnavailableView("No Collection Selected", systemImage: systemImage,
                                   description: Text("Choose a collection in the sidebar."))
                .readableWidth()
                .accessibilityIdentifier("no-collection-selected")
        }
    }
}
extension Color {
    /// Fills only (progress, bars): too light for text on white. Text and controls use the app tint, `motifAccentStrong`.
    static let motifAccent = Color(red: 0.43, green: 0.67, blue: 0.28)
    /// Deep enough for white text on it to stay readable; a step lighter in dark mode,
    /// where the light-mode green as text on the dark background falls under 4.5:1.
    static let motifAccentStrong = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.36, green: 0.62, blue: 0.22, alpha: 1) : UIColor(red: 0.24, green: 0.48, blue: 0.12, alpha: 1)
    })
}
