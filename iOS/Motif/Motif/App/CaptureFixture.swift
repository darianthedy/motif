#if DEBUG
import Foundation

/// Launch fixtures for the iPhone Duo capture suite (`DuoCaptureTests`), so every
/// state in the plan's §4 inventory can be opened on a fresh launch. Debug builds
/// only, on the memory backend: `-MotifFixture seed=games,engine,pending=2`.
///
/// - `seed=empty|collections|progress|games|solve`: the library to start from (see `CaptureSeed`).
/// - `hang-user`, `hang-load`, `fail-load`: the account never answers, or the library load hangs or fails.
/// - `hang-signin`, `fail-signin`, `fail-signout`, `hang-writes`, `fail-writes`.
/// - `offline-first`: signed in, offline, with nothing cached.
/// - `prod-account`: hide the dev-account footers.
/// - `pending=N`, `status=syncing|error`, `error`, `notice`: store and banner state after opening.
/// - `engine`: the scripted engine on every game route. `lines`, `eval-off`: the Analysis view toggles.
/// - `problem`: the Analysis view shows a move problem. `slow-reply`: the opponent takes 10 s to reply.
/// - `import=<name>`: prefills an import sheet with one of `CaptureSeed.importTexts`.
struct CaptureFixture: Sendable {
    static let current = CaptureFixture(UserDefaults.standard.string(forKey: "MotifFixture") ?? "")
    private let values: [String: String]
    init(_ text: String) {
        var values: [String: String] = [:]
        for item in text.split(separator: ",") {
            let parts = item.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if let key = parts.first, !key.isEmpty { values[key] = parts.count > 1 ? parts[1] : "" }
        }
        self.values = values
    }
    func has(_ key: String) -> Bool { values[key] != nil }
    subscript(_ key: String) -> String? { values[key] }
    var seed: String { values["seed"] ?? "" }

    /// The Analysis view's toggles persist, so each launch starts them from the fixture.
    func resetPreferences(_ defaults: UserDefaults = .standard) {
        defaults.set(!has("eval-off"), forKey: "evalBarShown")
        defaults.set(has("lines"), forKey: "engineLinesShown")
    }
    /// Applied once the store has opened.
    @MainActor func apply(to app: AppState) async {
        let store = app.store
        if let count = values["pending"].flatMap(Int.init), count > 0, let library = store.library, let puzzle = library.puzzles.first {
            let online = store.online
            store.online = false   // so the attempts stay in the outbox
            for n in 0..<count {
                try? await store.recordAttempt(Attempt(id: "pending-\(n)", puzzleId: puzzle.id, runId: nil, result: .solved, mistakes: 0, hinted: false, playedAt: epochMilliseconds()))
            }
            store.online = online
        }
        switch values["status"] {
        case "syncing": store.debugStatus(.syncing)
        case "error": store.debugStatus(.error("The server didn’t answer."))
        default: break
        }
        if has("error") { app.error = "That didn't save: The server didn’t answer." }
        if has("notice") { app.pinNotice("PGN copied.") }
    }
}

/// Faults for the capture fixtures, around the memory backend.
struct FixtureBackend: Backend {
    let base: MemoryBackend
    let fixture: CaptureFixture
    private func hang() async throws -> Never {
        while true { try await Task.sleep(for: .seconds(3600)) }
    }
    private func write() async throws {
        if fixture.has("hang-writes") { try await hang() }
        if fixture.has("fail-writes") { throw DataFailure(message: "The server didn’t answer.") }
    }
    func load() async throws -> Library {
        if fixture.has("hang-load") { try await hang() }
        if fixture.has("fail-load") { throw DataFailure(message: "The server didn’t answer.") }
        return await base.load()
    }
    func createCollections(_ collections: [Collection]) async throws { try await write(); try await base.createCollections(collections) }
    func renameCollection(_ id: String, _ name: String) async throws { try await write(); try await base.renameCollection(id, name) }
    func deleteCollection(_ id: String) async throws { try await write(); try await base.deleteCollection(id) }
    func importPuzzles(_ puzzles: [NewPuzzle]) async throws -> [Puzzle] { try await write(); return try await base.importPuzzles(puzzles) }
    func setComment(_ id: String, _ comment: String) async throws { try await write(); try await base.setComment(id, comment) }
    func setFlagged(_ id: String, _ flagged: Bool) async throws { try await write(); try await base.setFlagged(id, flagged) }
    func deletePuzzle(_ id: String) async throws { try await write(); try await base.deletePuzzle(id) }
    func saveRun(_ run: Run) async throws { try await write(); try await base.saveRun(run) }
    func deleteRun(_ id: String) async throws { try await write(); try await base.deleteRun(id) }
    func recordAttempts(_ attempts: [Attempt]) async throws { try await write(); try await base.recordAttempts(attempts) }
    func resetProgress() async throws { try await write(); try await base.resetProgress() }
    func createGameCollections(_ collections: [GameCollection]) async throws { try await write(); try await base.createGameCollections(collections) }
    func renameGameCollection(_ id: String, _ name: String) async throws { try await write(); try await base.renameGameCollection(id, name) }
    func deleteGameCollection(_ id: String) async throws { try await write(); try await base.deleteGameCollection(id) }
    func addGames(_ games: [NewGame]) async throws { try await write(); try await base.addGames(games) }
    func updateGame(_ id: String, _ changes: GameChanges) async throws { try await write(); try await base.updateGame(id, changes) }
    func placeGames(_ placements: [GamePlacement]) async throws { try await write(); try await base.placeGames(placements) }
    func deleteGames(_ ids: [String]) async throws { try await write(); try await base.deleteGames(ids) }
}

/// The libraries and import texts the capture fixtures start from. The default
/// library (no `seed`) stays as the UI tests expect it.
enum CaptureSeed {
    static func apply(_ seed: String, to library: inout Library) {
        switch seed {
        case "empty":
            library = Library()
        case "collections":
            library.puzzles = []; library.games = []
        case "progress":
            progress(&library)
        case "games":
            games(&library)
        case "solve":
            solve(&library)
        default: break
        }
    }
    /// Solved, missed and flagged puzzles, plus a session in progress in the first
    /// collection and a random one across everything.
    private static func progress(_ library: inout Library) {
        let ids = library.puzzles.map(\.id)
        guard ids.count >= 3 else { return }
        library.attempts = [
            Attempt(id: "seed-a0", puzzleId: ids[0], runId: nil, result: .solved, mistakes: 0, hinted: false, playedAt: 1),
            Attempt(id: "seed-a1", puzzleId: ids[1], runId: nil, result: .failed, mistakes: 2, hinted: true, playedAt: 2),
        ]
        if let index = library.puzzles.firstIndex(where: { $0.id == ids[2] }) { library.puzzles[index].flagged = true }
        let first = library.collections.first?.id ?? ""
        let inFirst = library.puzzles.filter { $0.collectionId == first }.map(\.id)
        library.runs = [
            Run(id: "seed-run", scope: first, mode: .ordered, queue: inFirst, startedAt: 3),
            Run(id: "seed-random", scope: SCOPE_ALL, mode: .randomGlobal, queue: ids, startedAt: 4),
        ]
        library.attempts.append(Attempt(id: "seed-a2", puzzleId: inFirst[0], runId: "seed-run", result: .solved, mistakes: 0, hinted: false, playedAt: 5))
        library.attempts.append(Attempt(id: "seed-a3", puzzleId: ids[0], runId: "seed-random", result: .solved, mistakes: 0, hinted: false, playedAt: 6))
    }
    /// A richer first game (a game note, a comment, five first moves, a variation),
    /// one with no moves, one before a promotion, and enough others to fill a list.
    private static func games(_ library: inout Library) {
        let rich = """
        [Event "Club championship"]
        [Site "Bangkok"]
        [Date "2026.10.12"]
        [Round "4"]
        [White "Me"]
        [Black "Club friend"]
        [Result "1-0"]
        [Opening "Ruy Lopez"]

        {A long game against a regular opponent.} 1. e4 {Best by test.} (1. d4 d5) (1. c4 e5) (1. Nf3 Nf6) (1. g3 g6) 1... e5 2. Nf3 (2. Bc4 Nc6) Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Na5 10. Bc2 c5 11. d4 Qc7 1-0
        """
        let others: [(String, String, String, String)] = [
            ("Alpha", "Beta", "1/2-1/2", "1. d4 d5 2. c4 e6 3. Nc3 Nf6 1/2-1/2"),
            ("Me", "Engine", "0-1", "1. e4 c5 2. Nf3 d6 3. d4 cxd4 0-1"),
            ("Club friend", "Me", "1-0", "1. c4 e5 2. Nc3 Nf6 1-0"),
            ("Carlsen", "Nakamura", "*", "1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 *"),
            ("Me", "Coach", "1/2-1/2", "1. d4 Nf6 2. c4 g6 1/2-1/2"),
        ]
        let collection = library.gameCollections.first?.id ?? "sample-games"
        library.gameCollections.append(GameCollection(id: "sample-openings", name: "Openings", createdAt: 1))
        var games = [
            Game(id: "sample-game", collectionId: collection, position: 0, pgn: rich, orientation: .white, addedAt: 0),
            Game(id: "sample-empty", collectionId: collection, position: 1, pgn: "[White \"New game\"]\n[Black \"?\"]\n\n*", orientation: .white, addedAt: 0),
            Game(id: "sample-promotion", collectionId: collection, position: 2,
                 pgn: "[White \"Endgame study\"]\n[Black \"?\"]\n[SetUp \"1\"]\n[FEN \"7k/4P3/8/8/8/8/8/6K1 w - - 0 1\"]\n\n*", orientation: .white, addedAt: 0),
        ]
        for (n, other) in others.enumerated() {
            games.append(Game(id: "sample-other-\(n)", collectionId: collection, position: games.count,
                              pgn: "[Event \"Club night\"]\n[Round \"\(n + 1)\"]\n[White \"\(other.0)\"]\n[Black \"\(other.1)\"]\n[Result \"\(other.2)\"]\n\n\(other.3)",
                              orientation: .white, addedAt: 0))
        }
        games.append(Game(id: "sample-opening", collectionId: "sample-openings", position: 0, pgn: "[White \"Italian\"]\n[Black \"?\"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bc4 *", orientation: .white, addedAt: 0))
        library.games = games
    }
    /// A collection for the session states: an opponent reply, a promotion, and a long comment.
    private static func solve(_ library: inout Library) {
        let id = "sample-solve"
        let long = Array(repeating: "The rook lift decides: every black defender is a tempo short, and the back rank has no luft.", count: 6).joined(separator: " ")
        let content: [PuzzleContent] = [
            PuzzleContent(fen: "6k1/5p1p/8/8/8/8/8/3R2K1 w - - 0 1", solutions: [["d1d8", "g8g7", "d8d7"]], tags: ["backRank"], comment: "Only square."),
            PuzzleContent(fen: "7k/4P3/8/8/8/8/8/6K1 w - - 0 1", solutions: [["e7e8q"]], tags: ["promotion"]),
            PuzzleContent(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", solutions: [["a1a8"]], tags: ["backRank", "mateIn1"], comment: long, rating: 900),
        ]
        library.collections.append(Collection(id: id, name: "Session states", createdAt: Int64(library.collections.count)))
        library.puzzles += content.enumerated().map { n, content in
            Puzzle(content: content, id: id + "-\(n)", collectionId: id, position: n, addedAt: 0)
        }
    }
    /// `import=<name>` texts for the two import sheets.
    static let importTexts: [String: String] = [
        "valid": #"{"collection":"Back-rank mates","puzzles":[{"fen":"6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1","solutions":[["a1a8"]]},{"fen":"6k1/5ppp/8/8/8/8/8/1R4K1 w - - 0 1","solutions":[["b1b8"]]}]}"#,
        "new": #"{"collection":"Forks","puzzles":[{"fen":"4k3/8/8/3N4/8/8/8/4K3 w - - 0 1","solutions":[["d5c7"]]},{"fen":"6k1/5ppp/8/8/8/8/8/1R4K1 w - - 0 1","solutions":[["b1b8"]]}]}"#,
        "rejects": #"{"collection":"Forks","puzzles":[{"fen":"6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1","solutions":[["a1a8"]]},{"fen":"not a fen","solutions":[["a1a8"]]},{"fen":"6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1","solutions":[["h1h8"]]}]}"#,
        "all-rejected": #"{"collection":"Broken","puzzles":[{"fen":"not a fen","solutions":[["a1a8"]]},{"fen":"8/8/8/8/8/8/8/8 w - - 0 1","solutions":[]}]}"#,
        "multi": #"[{"collection":"Forks","puzzles":[{"fen":"4k3/8/8/3N4/8/8/8/4K3 w - - 0 1","solutions":[["d5c7"]]}]},{"collection":"Pins","puzzles":[{"fen":"6k1/5ppp/8/8/8/8/8/1R4K1 w - - 0 1","solutions":[["b1b8"]]}]},{"collection":"Skewers","puzzles":[{"fen":"6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1","solutions":[["a1a8"]]}]}]"#,
        "pgn": "[White \"Alpha\"]\n[Black \"Beta\"]\n\n1. e4 e5 *\n\n[White \"Me\"]\n[Black \"Club friend\"]\n\n1. d4 d5 *",
        "pgn-many": (1...7).map { "[White \"Player \($0)\"]\n[Black \"Opponent \($0)\"]\n\n1. e4 e5 *" }.joined(separator: "\n\n"),
        "pgn-errors": "[White \"Alpha\"]\n[Black \"Beta\"]\n1. e4 e5 *\n\n[White \"Bad\"]\n1. e4 e4 *\n\n[White \"Me\"]\n[Black \"Club friend\"]\n1. d4 d5 *",
    ]
    static var importText: String? { CaptureFixture.current["import"].flatMap { importTexts[$0] } }
}
#endif
