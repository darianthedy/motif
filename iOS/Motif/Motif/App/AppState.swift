import SwiftUI
import Observation

enum RootState: Equatable { case unknown, signedOut, waiting, library }
enum AppTab: Hashable { case puzzles, games, account }

@Observable @MainActor
final class AppState {
    let store: LibraryStore
    let usingDevAccount: Bool
    var tab = AppTab.puzzles
    var notice: String?
    var launchRoute: String?
    @ObservationIgnored private let connectivity = Connectivity()
    @ObservationIgnored private let debug: Bool
    var root: RootState {
        if !store.userKnown { return .unknown }
        if store.user == nil { return .signedOut }
        return store.library == nil ? .waiting : .library
    }
    init(store: LibraryStore, usingDevAccount: Bool = true, debug: Bool = false, route: String? = nil) {
        self.store = store; self.usingDevAccount = usingDevAccount; self.debug = debug; launchRoute = route
        if route == "account" { tab = .account }
        if route?.hasPrefix("game") == true { tab = .games }
    }
    static func live() -> AppState {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "MotifMemoryBackend") {
            let seeded = UserDefaults.standard.bool(forKey: "MotifSeedSamples")
            let route = UserDefaults.standard.string(forKey: "MotifRoute")
            let account = ScreenshotAccount(seed: seeded, signedIn: seeded && route != "signin")
            let paths = StoragePaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("Motif-debug-" + newID()))
            let defaults = UserDefaults(suiteName: "Motif-debug-" + newID())!
            return AppState(store: LibraryStore(account: account, cache: Cache(storage: paths), outbox: Outbox(storage: paths), defaults: defaults), debug: true, route: route)
        }
        #endif
        let url = AppConfig.neonBaseURL
        let account: any Account = url.map { NeonAuth(baseURL: $0) } ?? DevAccount()
        return AppState(store: LibraryStore(account: account), usingDevAccount: url == nil)
    }
    func open() async {
        if !debug { connectivity.start(store) }
        await store.open()
    }
    func signOut() async {
        do { try await store.signOut(); tab = .puzzles; launchRoute = nil }
        catch { notice = error.localizedDescription }
    }
    @discardableResult
    func edit(_ action: @Sendable (any Backend) async throws -> Void, done: String? = nil) async -> Bool {
        do { try await store.write(action); notice = done; return true }
        catch { notice = "That didn't save: " + error.localizedDescription; return false }
    }
}

#if DEBUG
/// Clean per launch; only deterministic bundled samples are used for screenshots.
actor ScreenshotAccount: Account {
    private var user: User?
    private let memory: MemoryBackend
    init(seed: Bool, signedIn: Bool) {
        user = signedIn ? User(id: "sample", email: "sample@motif.local") : nil
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
        }
        memory = MemoryBackend(library)
    }
    func currentUser() -> User? { user }
    func signIn(_ email: String, _ password: String) { user = User(id: email, email: email) }
    func signUp(_ email: String, _ password: String) { signIn(email, password) }
    func signOut() { user = nil }
    func backend(_ user: User) -> any Backend { memory }
}
#endif
