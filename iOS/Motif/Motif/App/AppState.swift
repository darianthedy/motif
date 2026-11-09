import SwiftUI
import Observation

enum RootState: Equatable { case unknown, signedOut, waiting, library }
enum AppTab: Hashable { case puzzles, games }

@Observable @MainActor
final class AppState {
    let store: LibraryStore
    let usingDevAccount: Bool
    var tab = AppTab.puzzles
    /// A success shown as a transient toast; `showNotice` clears it after a few seconds.
    private(set) var notice: String?
    /// A failure shown as a persistent banner until dismissed.
    var error: String?
    // Navigation model (Duo plan D02). Each tab is one `NavigationSplitView`: the
    // collection selected in the sidebar is the detail column's root, the path is
    // what is pushed on top of it, and the column visibility is the tab's own.
    // All of it lives here rather than in the views, so folding (a size-class
    // change that collapses or expands the split view) never loses it.
    /// The puzzle collection shown in the Puzzles detail column; nil shows the home list alone.
    var puzzlesCollection: String?
    /// Pushed on top of `puzzlesCollection` (the puzzle list, a puzzle).
    var puzzlesPath: [PuzzleRoute] = [] { didSet { puzzlesColumns.follow(board: puzzlesPath.contains(where: \.isBoard)) } }
    var puzzlesColumns = TabColumns()
    /// The game collection shown in the Games detail column.
    var gamesCollection: String?
    /// Pushed on top of `gamesCollection` (a game's Analysis view).
    var gamesPath: [GamesRoute] = [] { didSet { gamesColumns.follow(board: gamesPath.contains(where: \.isBoard)) } }
    var gamesColumns = TabColumns()
    var session: SessionRoute?
    var importingPuzzles = false
    /// The Account sheet, opened from the avatar button on either home screen.
    var showingAccount = false
    var launchRoute: String?
    @ObservationIgnored private let connectivity = Connectivity()
    @ObservationIgnored private let debug: Bool
    @ObservationIgnored private var noticeTimer: Task<Void, Never>?
    var root: RootState {
        if !store.userKnown { return .unknown }
        if store.user == nil { return .signedOut }
        return store.library == nil ? .waiting : .library
    }
    init(store: LibraryStore, usingDevAccount: Bool = true, debug: Bool = false, route: String? = nil) {
        self.store = store; self.usingDevAccount = usingDevAccount; self.debug = debug; launchRoute = route
        if route == "account" { showingAccount = true }
        if route?.hasPrefix("game") == true { tab = .games }
    }
    static func live() -> AppState {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "MotifMemoryBackend") {
            let seeded = UserDefaults.standard.bool(forKey: "MotifSeedSamples")
            let route = UserDefaults.standard.string(forKey: "MotifRoute")
            let fixture = CaptureFixture.current
            fixture.resetPreferences()
            let account = ScreenshotAccount(seed: seeded, signedIn: seeded && route != "signin", unreadableGame: route == "game-unreadable", fixture: fixture)
            let paths = StoragePaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("Motif-debug-" + newID()))
            let defaults = UserDefaults(suiteName: "Motif-debug-" + newID())!
            // Signed in on an earlier launch, offline now, with nothing cached.
            let offlineFirst = fixture.has("offline-first")
            if offlineFirst { defaults.set(try? JSONEncoder().encode(ScreenshotAccount.sample), forKey: "motif:user") }
            let store = LibraryStore(account: account, cache: Cache(storage: paths), outbox: Outbox(storage: paths), defaults: defaults, online: !offlineFirst)
            return AppState(store: store, usingDevAccount: !fixture.has("prod-account"), debug: true, route: route)
        }
        #endif
        let url = AppConfig.neonBaseURL
        let account: any Account = url.map { NeonAuth(baseURL: $0) } ?? DevAccount()
        return AppState(store: LibraryStore(account: account), usingDevAccount: url == nil)
    }
    func open() async {
        if !debug { connectivity.start(store) }
        await store.open()
        #if DEBUG
        if debug && UserDefaults.standard.bool(forKey: "MotifOffline") { await store.setOnline(false) }
        if debug { await CaptureFixture.current.apply(to: self) }
        #endif
    }
    func begin(_ scope: String, _ mode: SessionMode, _ ids: [String]) async {
        guard !ids.isEmpty else { return }
        let run = Run(id: newID(), scope: scope, mode: mode, queue: makeQueue(mode, ids), startedAt: epochMilliseconds())
        do { try await store.startRun(run); session = SessionRoute(scope: scope) }
        catch { self.error = error.localizedDescription }
    }
    /// Opens a full route, as callers and launch routes give it (`[.collection(id), .puzzles(id), .puzzle(…)]`):
    /// a leading `.collection` becomes the sidebar selection and the rest the detail path. A route
    /// without one is pushed on the current selection; an empty route clears both.
    func openPuzzles(_ route: [PuzzleRoute]) {
        if route.isEmpty { puzzlesCollection = nil; puzzlesPath = [] }
        else if case .collection(let id) = route[0] { puzzlesCollection = id; puzzlesPath = Array(route.dropFirst()) }
        else { puzzlesPath = route }
    }
    /// `openPuzzles(_:)` for the Games tab.
    func openGames(_ route: [GamesRoute]) {
        if route.isEmpty { gamesCollection = nil; gamesPath = [] }
        else if case .collection(let id) = route[0] { gamesCollection = id; gamesPath = Array(route.dropFirst()) }
        else { gamesPath = route }
    }
    /// The sidebar's selection binding: picking a collection (or another one) clears what was pushed on the last.
    var puzzlesSelection: String? {
        get { puzzlesCollection }
        set { if newValue != puzzlesCollection { puzzlesPath = [] }; puzzlesCollection = newValue }
    }
    var gamesSelection: String? {
        get { gamesCollection }
        set { if newValue != gamesCollection { gamesPath = [] }; gamesCollection = newValue }
    }
    func signOut() async {
        do { try await store.signOut(); tab = .puzzles; showingAccount = false; launchRoute = nil; openPuzzles([]); openGames([]); session = nil }
        catch { self.error = error.localizedDescription }
    }
    @discardableResult
    func edit(_ action: @Sendable (any Backend) async throws -> Void, done: String? = nil) async -> Bool {
        do { try await store.write(action); if let done { showNotice(done) }; return true }
        catch { self.error = "That didn't save: " + error.localizedDescription; return false }
    }
    func showNotice(_ text: String) {
        notice = text
        AccessibilityNotification.Announcement(text).post()
        noticeTimer?.cancel()
        noticeTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self?.notice == text else { return }
            self?.notice = nil
        }
    }
    func dismissNotice() { noticeTimer?.cancel(); notice = nil }
    #if DEBUG
    /// A toast that stays up for a screenshot.
    func pinNotice(_ text: String) { noticeTimer?.cancel(); notice = text }
    #endif
}

/// One tab's split view column visibility. A pushed board screen (puzzle detail, the Analysis
/// view) hides the sidebar (`.detailOnly`); popping it restores what was shown before.
struct TabColumns: Equatable {
    var visibility = NavigationSplitViewVisibility.automatic
    /// What `visibility` was when a board was pushed; nil while no board is shown.
    private(set) var beforeBoard: NavigationSplitViewVisibility?
    mutating func follow(board: Bool) {
        if board, beforeBoard == nil { beforeBoard = visibility; visibility = .detailOnly }
        else if !board, let previous = beforeBoard { visibility = previous; beforeBoard = nil }
    }
}
extension PuzzleRoute { var isBoard: Bool { if case .puzzle = self { return true }; return false } }
extension GamesRoute { var isBoard: Bool { if case .game = self { return true }; return false } }

#if DEBUG
/// Clean per launch; only deterministic bundled samples are used for screenshots.
actor ScreenshotAccount: Account {
    static let sample = User(id: "sample", email: "sample@motif.local")
    private var user: User?
    private let memory: MemoryBackend
    private let fixture: CaptureFixture
    init(seed: Bool, signedIn: Bool, unreadableGame: Bool = false, fixture: CaptureFixture = CaptureFixture("")) {
        self.fixture = fixture
        user = signedIn ? Self.sample : nil
        var library = Library()
        if seed {
            for name in ["sample-back-rank", "sample-missing-piece"] {
                guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                      let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for group in importJson(text).groups {
                    let id = name
                    library.collections.append(Collection(id: id, name: group.name ?? name, createdAt: Int64(library.collections.count)))
                    library.puzzles += group.puzzles.enumerated().map { n, content in
                        Puzzle(content: content, id: id + "-\(n)", collectionId: id, position: n, addedAt: 0)
                    }
                }
            }
            library.gameCollections = [GameCollection(id: "sample-games", name: "Study games", createdAt: 0)]
            library.games = [Game(id: "sample-game", collectionId: "sample-games", position: 0,
                pgn: "[White \"White\"]\n[Black \"Black\"]\n\n1. e4 e5 2. Nf3 (2. Bc4 Nc6) Nc6 3. Bb5 *", orientation: .white, addedAt: 0)]
            // Only for its own route, so other routes keep the one-game collection.
            if unreadableGame {
                library.games.insert(Game(id: "sample-unreadable", collectionId: "sample-games", position: 0,
                    pgn: "[White \"Club friend\"]\n[Black \"Me\"]\n\n1. e4 e4 *", orientation: .white, addedAt: 0), at: 0)
                library.games[1].position = 1
            }
        }
        if seed { CaptureSeed.apply(fixture.seed, to: &library) }
        memory = MemoryBackend(library)
    }
    private static func hang() async throws -> Never { while true { try await Task.sleep(for: .seconds(3600)) } }
    func currentUser() async throws -> User? {
        if fixture.has("hang-user") { try await Self.hang() }
        return user
    }
    func signIn(_ email: String, _ password: String) async throws {
        if fixture.has("hang-signin") { try await Self.hang() }
        if fixture.has("fail-signin") { throw DataFailure(message: "Wrong email or password.") }
        user = User(id: email, email: email)
    }
    func signUp(_ email: String, _ password: String) async throws { try await signIn(email, password) }
    func signOut() throws {
        if fixture.has("fail-signout") { throw DataFailure(message: "Couldn’t sign out: the server didn’t answer.") }
        user = nil
    }
    func backend(_ user: User) -> any Backend { FixtureBackend(base: memory, fixture: fixture) }
}
#endif
