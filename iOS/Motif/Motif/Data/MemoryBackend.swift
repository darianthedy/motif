import Foundation

/// One account without a database. Value copies keep reads and caller input
/// isolated. DevAccount optionally persists every write, so relaunch survives.
actor MemoryBackend: Backend {
    private var library: Library
    private let fileURL: URL?

    init(_ initial: Library = Library(), fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode(Library.self, from: data) { library = stored }
        else { library = initial }
    }
    func load() -> Library { library }
    private func persist() throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(library).write(to: fileURL, options: .atomic)
    }
    func createCollections(_ collections: [Collection]) throws {
        for c in collections where library.collections.contains(where: { $0.id == c.id }) {
            throw DataFailure(message: "Collection \(c.id) already exists")
        }
        library.collections += collections
        try persist()
    }
    func renameCollection(_ id: String, _ name: String) throws {
        for i in library.collections.indices where library.collections[i].id == id { library.collections[i].name = name }
        try persist()
    }
    func deleteCollection(_ id: String) throws {
        library.collections.removeAll { $0.id == id }
        library.runs.removeAll { $0.scope == id }
        let gone = Set(library.puzzles.filter { $0.collectionId == id }.map(\.id))
        dropPuzzles(gone)
        try persist()
    }
    func importPuzzles(_ puzzles: [NewPuzzle]) throws -> [Puzzle] {
        var stored: [Puzzle] = []
        for incoming in distinctPuzzles(puzzles) {
            guard library.collections.contains(where: { $0.id == incoming.collectionId }) else {
                throw DataFailure(message: "No collection \(incoming.collectionId)")
            }
            let index = library.puzzles.firstIndex {
                $0.collectionId == incoming.collectionId && contentKey($0) == contentKey(incoming)
            }
            var puzzle = Puzzle(id: index.map { library.puzzles[$0].id } ?? newID(),
                                collectionId: incoming.collectionId, position: incoming.position,
                                fen: incoming.fen, solutions: incoming.solutions, addPiece: incoming.addPiece,
                                tags: incoming.tags, comment: incoming.comment, sourceId: incoming.sourceId,
                                rating: incoming.rating, addedAt: index.map { library.puzzles[$0].addedAt } ?? epochMilliseconds())
            if let index { puzzle.flagged = library.puzzles[index].flagged; library.puzzles[index] = puzzle }
            else { library.puzzles.append(puzzle) }
            stored.append(puzzle)
        }
        try persist()
        return stored
    }
    func setComment(_ id: String, _ comment: String) throws {
        for i in library.puzzles.indices where library.puzzles[i].id == id {
            library.puzzles[i].comment = cleanBackendComment(comment)
        }
        try persist()
    }
    func setFlagged(_ id: String, _ flagged: Bool) throws {
        for i in library.puzzles.indices where library.puzzles[i].id == id { library.puzzles[i].flagged = flagged ? true : nil }
        try persist()
    }
    private func dropPuzzles(_ ids: Set<String>) {
        library.puzzles.removeAll { ids.contains($0.id) }
        library.attempts.removeAll { ids.contains($0.puzzleId) }
    }
    func deletePuzzle(_ id: String) throws { dropPuzzles([id]); try persist() }
    func saveRun(_ run: Run) throws {
        let held = library.runs.first { $0.scope == run.scope }
        if let held, held.startedAt >= run.startedAt { return }
        if let held { removeRun(held.id) }
        library.runs.append(run)
        try persist()
    }
    private func removeRun(_ id: String) {
        library.runs.removeAll { $0.id == id }
        for i in library.attempts.indices where library.attempts[i].runId == id { library.attempts[i].runId = nil }
    }
    func deleteRun(_ id: String) throws { removeRun(id); try persist() }
    func recordAttempts(_ attempts: [Attempt]) throws {
        let puzzles = Set(library.puzzles.map(\.id)), runs = Set(library.runs.map(\.id))
        var stored = Set(library.attempts.map(\.id))
        for var attempt in attempts where !stored.contains(attempt.id) && puzzles.contains(attempt.puzzleId) {
            stored.insert(attempt.id)
            if let runId = attempt.runId, runId.isEmpty || !runs.contains(runId) { attempt.runId = nil }
            library.attempts.append(attempt)
        }
        try persist()
    }
    func resetProgress() throws { library.attempts = []; library.runs = []; try persist() }
    func createGameCollections(_ collections: [GameCollection]) throws {
        for c in collections where library.gameCollections.contains(where: { $0.id == c.id }) {
            throw DataFailure(message: "Game collection \(c.id) already exists")
        }
        library.gameCollections += collections; try persist()
    }
    func renameGameCollection(_ id: String, _ name: String) throws {
        for i in library.gameCollections.indices where library.gameCollections[i].id == id { library.gameCollections[i].name = name }
        try persist()
    }
    func deleteGameCollection(_ id: String) throws {
        library.gameCollections.removeAll { $0.id == id }; library.games.removeAll { $0.collectionId == id }; try persist()
    }
    func addGames(_ games: [NewGame]) throws {
        for game in games {
            guard library.gameCollections.contains(where: { $0.id == game.collectionId }) else {
                throw DataFailure(message: "No game collection \(game.collectionId)")
            }
            if library.games.contains(where: { $0.id == game.id }) { throw DataFailure(message: "Game \(game.id) already exists") }
        }
        let now = epochMilliseconds()
        library.games += games.map {
            Game(id: $0.id, collectionId: $0.collectionId, position: $0.position,
                 pgn: $0.pgn, orientation: $0.orientation, addedAt: now)
        }
        try persist()
    }
    func updateGame(_ id: String, _ changes: GameChanges) throws {
        for i in library.games.indices where library.games[i].id == id {
            if let pgn = changes.pgn { library.games[i].pgn = pgn }
            if let orientation = changes.orientation { library.games[i].orientation = orientation }
        }
        try persist()
    }
    func placeGames(_ placements: [GamePlacement]) throws {
        for placement in placements {
            guard library.gameCollections.contains(where: { $0.id == placement.collectionId }) else {
                throw DataFailure(message: "No game collection \(placement.collectionId)")
            }
            for i in library.games.indices where library.games[i].id == placement.id {
                library.games[i].collectionId = placement.collectionId; library.games[i].position = placement.position
            }
        }
        try persist()
    }
    func deleteGames(_ ids: [String]) throws { let ids = Set(ids); library.games.removeAll { ids.contains($0.id) }; try persist() }
}
