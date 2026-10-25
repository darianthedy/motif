/// A puzzle on its way in: the database assigns id and time. A file cannot
/// clear a flag, so NewPuzzle has no flagged field.
struct NewPuzzle: Hashable, Codable, Sendable, PuzzleIdentity {
    var collectionId: String
    var position: Int
    var fen: String
    var solutions: [[Uci]]
    var addPiece: Placement?
    var tags: [String]
    var comment: String?
    var sourceId: String?
    var rating: Double?

    init(_ content: PuzzleContent, collectionId: String, position: Int) {
        self.collectionId = collectionId; self.position = position
        fen = content.fen; solutions = content.solutions; addPiece = content.addPiece
        tags = content.tags; comment = content.comment
        sourceId = content.sourceId; rating = content.rating
    }
}

/// A collection id or one of the two scopes spanning the whole library.
typealias RunScope = String
let SCOPE_ALL = "all"
let SCOPE_REVIEW = "review"

/// Only immutable starting facts are stored; attempts derive current progress.
struct Run: Hashable, Codable, Sendable {
    var id: String
    var scope: RunScope
    var mode: SessionMode
    var queue: [String]
    var startedAt: Int64
}

enum AttemptResult: String, Codable, Sendable { case solved, failed, skipped }

struct Attempt: Hashable, Codable, Sendable {
    /// Device-generated id makes repeat uploads idempotent.
    var id: String
    var puzzleId: String
    /// Nil once the run it belonged to is gone.
    var runId: String?
    var result: AttemptResult
    var mistakes: Int
    var hinted: Bool
    var playedAt: Int64
}

/// The account's library. Backend behavior arrives in P05.
struct Library: Equatable, Codable, Sendable {
    var collections: [Collection] = []
    var puzzles: [Puzzle] = []
    var runs: [Run] = []
    var attempts: [Attempt] = []
    var gameCollections: [GameCollection] = []
    var games: [Game] = []
}

func emptyLibrary() -> Library { Library() }
import Foundation


/// Older cached copies acquire new row kinds as empty arrays.
extension Library {
    private enum Keys: String, CodingKey { case collections, puzzles, runs, attempts, gameCollections, games }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        collections = try c.decodeIfPresent([Collection].self, forKey: .collections) ?? []
        puzzles = try c.decodeIfPresent([Puzzle].self, forKey: .puzzles) ?? []
        runs = try c.decodeIfPresent([Run].self, forKey: .runs) ?? []
        attempts = try c.decodeIfPresent([Attempt].self, forKey: .attempts) ?? []
        gameCollections = try c.decodeIfPresent([GameCollection].self, forKey: .gameCollections) ?? []
        games = try c.decodeIfPresent([Game].self, forKey: .games) ?? []
    }
}

struct DataFailure: Error, Equatable, CustomStringConvertible, LocalizedError, Sendable {
    var message: String
    var description: String { message }
    var errorDescription: String? { message }
}
struct GameChanges: Sendable {
    var pgn: String? = nil
    var orientation: Side? = nil
}

/// The account's source of truth. Edits go straight to it; only immutable play
/// records enter the offline outbox. All implementations obey the same rules.
protocol Backend: Sendable {
    func load() async throws -> Library
    func createCollections(_ collections: [Collection]) async throws
    func renameCollection(_ id: String, _ name: String) async throws
    func deleteCollection(_ id: String) async throws
    func importPuzzles(_ puzzles: [NewPuzzle]) async throws -> [Puzzle]
    func setComment(_ id: String, _ comment: String) async throws
    func setFlagged(_ id: String, _ flagged: Bool) async throws
    func deletePuzzle(_ id: String) async throws
    func saveRun(_ run: Run) async throws
    func deleteRun(_ id: String) async throws
    func recordAttempts(_ attempts: [Attempt]) async throws
    func resetProgress() async throws
    func createGameCollections(_ collections: [GameCollection]) async throws
    func renameGameCollection(_ id: String, _ name: String) async throws
    func deleteGameCollection(_ id: String) async throws
    func addGames(_ games: [NewGame]) async throws
    func updateGame(_ id: String, _ changes: GameChanges) async throws
    func placeGames(_ placements: [GamePlacement]) async throws
    func deleteGames(_ ids: [String]) async throws
}

func cleanBackendComment(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: Uci.whitespace))
    return trimmed.isEmpty ? nil : trimmed
}
/// Last entry wins, at its last occurrence. Postgres rejects updating a row
/// twice in one upsert; identity includes the collection as well as content.
func distinctPuzzles(_ puzzles: [NewPuzzle]) -> [NewPuzzle] {
    var out: [NewPuzzle] = []
    for puzzle in puzzles {
        let key = contentKey(puzzle)
        out.removeAll { $0.collectionId == puzzle.collectionId && contentKey($0) == key }
        out.append(puzzle)
    }
    return out
}
func epochMilliseconds() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }
func newID() -> String { UUID().uuidString.lowercased() }

let CHUNK = 200
func dataChunks<T>(_ items: [T]) -> [[T]] {
    stride(from: 0, to: items.count, by: CHUNK).map { Array(items[$0..<min($0 + CHUNK, items.count)]) }
}
func isoTime(_ ms: Int64) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
}
func rowTime(_ value: JSONValue?) throws -> Int64 {
    guard let text = value?.text else { throw DataFailure(message: "Not a timestamp") }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: text)
    if date == nil { formatter.formatOptions = [.withInternetDateTime]; date = formatter.date(from: text) }
    guard let date else { throw DataFailure(message: "Not a timestamp: \(text)") }
    return Int64((date.timeIntervalSince1970 * 1000).rounded())
}
extension Dictionary where Key == String, Value == JSONValue {
    func text(_ key: String) throws -> String {
        guard let text = self[key]?.text else { throw DataFailure(message: "Missing \(key)") }
        return text
    }
    func integer(_ key: String) throws -> Int {
        guard let value = self[key]?.numeric, value.isFinite,
              value >= Double(Int.min), value < Double(Int.max) else { throw DataFailure(message: "Missing \(key)") }
        return Int(value)
    }
    func decode<T: Decodable>(_ key: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self[key] ?? .null))
    }
}
func puzzleRow(_ puzzle: NewPuzzle) -> Row {
    [
        "collection_id": .string(puzzle.collectionId), "position": .number(Double(puzzle.position)),
        "content_key": .string(contentKey(puzzle)), "fen": .string(puzzle.fen),
        "solutions": .array(puzzle.solutions.map { .strings($0.map(\.text)) }),
        "add_piece": puzzle.addPiece.map { .string(placementText($0)) } ?? .null,
        "tags": .strings(puzzle.tags), "comment": puzzle.comment.map(JSONValue.string) ?? .null,
        "source_id": puzzle.sourceId.map(JSONValue.string) ?? .null,
        "rating": puzzle.rating.map(JSONValue.number) ?? .null,
    ]
}
func puzzleFrom(_ row: Row) throws -> Puzzle {
    try Puzzle(id: row.text("id"), collectionId: row.text("collection_id"), position: row.integer("position"),
               fen: row.text("fen"), solutions: row.decode("solutions"), addPiece: row["add_piece"]?.text.flatMap(parsePlacement),
               tags: row["tags"]?.items?.compactMap(\.text) ?? [], comment: row["comment"]?.text,
               flagged: row["flagged"]?.boolean == true ? true : nil, sourceId: row["source_id"]?.text,
               rating: row["rating"]?.numeric, addedAt: rowTime(row["added_at"]))
}
func attemptRow(_ attempt: Attempt) -> Row {
    ["id": .string(attempt.id), "puzzle_id": .string(attempt.puzzleId),
     "run_id": attempt.runId.map(JSONValue.string) ?? .null, "result": .string(attempt.result.rawValue),
     "mistakes": .number(Double(attempt.mistakes)), "hinted": .bool(attempt.hinted),
     "played_at": .string(isoTime(attempt.playedAt))]
}
func gameFrom(_ row: Row) throws -> Game {
    try Game(id: row.text("id"), collectionId: row.text("collection_id"), position: row.integer("position"),
             pgn: row.text("pgn"), orientation: row["orientation"]?.text == "b" ? .black : .white,
             addedAt: rowTime(row["added_at"]))
}

/// Line-for-line backend policy over a small Rest protocol. RLS is enforced by
/// the server; this client never supplies an account id for inserted rows.
struct RestBackend: Backend {
    let rest: any Rest
    let userId: String
    func load() async throws -> Library {
        async let c = rest.select("collections")
        async let p = rest.select("puzzles")
        async let r = rest.select("runs")
        async let a = rest.select("attempts")
        async let gc = rest.select("game_collections")
        async let g = rest.select("games")
        let (collections, puzzles, runs, attempts, gameCollections, games) = try await (c, p, r, a, gc, g)
        return try Library(
            collections: collections.map { try Collection(id: $0.text("id"), name: $0.text("name"), createdAt: rowTime($0["created_at"])) },
            puzzles: puzzles.map(puzzleFrom),
            runs: runs.map {
                try Run(id: $0.text("id"), scope: $0.text("scope"), mode: $0.decode("mode"),
                        queue: $0.decode("queue"), startedAt: rowTime($0["started_at"]))
            },
            attempts: attempts.map {
                try Attempt(id: $0.text("id"), puzzleId: $0.text("puzzle_id"), runId: $0["run_id"]?.text,
                            result: $0.decode("result"), mistakes: $0.integer("mistakes"),
                            hinted: $0["hinted"]?.boolean ?? false, playedAt: rowTime($0["played_at"]))
            },
            gameCollections: gameCollections.map { try GameCollection(id: $0.text("id"), name: $0.text("name"), createdAt: rowTime($0["created_at"])) },
            games: games.map(gameFrom))
    }
    func createCollections(_ collections: [Collection]) async throws {
        if collections.isEmpty { return }
        _ = try await rest.insert("collections", collections.map {
            ["id": .string($0.id), "name": .string($0.name), "created_at": .string(isoTime($0.createdAt))]
        })
    }
    func renameCollection(_ id: String, _ name: String) async throws {
        try await rest.update("collections", ["name": .string(name)], [.eq("id", .string(id))])
    }
    func deleteCollection(_ id: String) async throws {
        try await rest.delete("runs", [.eq("scope", .string(id))])
        try await rest.delete("collections", [.eq("id", .string(id))])
    }
    func importPuzzles(_ puzzles: [NewPuzzle]) async throws -> [Puzzle] {
        var stored: [Puzzle] = []
        for chunk in dataChunks(distinctPuzzles(puzzles)) {
            let rows = try await rest.insert("puzzles", chunk.map(puzzleRow),
                                             UpsertOptions(onConflict: ["collection_id", "content_key"]))
            stored += try rows.map(puzzleFrom)
        }
        return stored
    }
    func setComment(_ id: String, _ comment: String) async throws {
        try await rest.update("puzzles", ["comment": cleanBackendComment(comment).map(JSONValue.string) ?? .null], [.eq("id", .string(id))])
    }
    func setFlagged(_ id: String, _ flagged: Bool) async throws {
        try await rest.update("puzzles", ["flagged": .bool(flagged)], [.eq("id", .string(id))])
    }
    func deletePuzzle(_ id: String) async throws { try await rest.delete("puzzles", [.eq("id", .string(id))]) }
    func saveRun(_ run: Run) async throws {
        try await rest.delete("runs", [.eq("scope", .string(run.scope)), .lt("started_at", .string(isoTime(run.startedAt)))])
        _ = try await rest.insert("runs", [[
            "id": .string(run.id), "scope": .string(run.scope), "mode": .string(run.mode.rawValue),
            "queue": .strings(run.queue), "started_at": .string(isoTime(run.startedAt)),
        ]], UpsertOptions(onConflict: ["user_id", "scope"], ignoreDuplicates: true))
    }
    func deleteRun(_ id: String) async throws { try await rest.delete("runs", [.eq("id", .string(id))]) }
    private func existing(_ table: String, _ ids: [String]) async throws -> Set<String> {
        var found: Set<String> = []
        for chunk in dataChunks(Array(Set(ids))) {
            let rows = try await rest.select(table, [.in("id", chunk.map(JSONValue.string))])
            for row in rows { found.insert(try row.text("id")) }
        }
        return found
    }
    func recordAttempts(_ attempts: [Attempt]) async throws {
        if attempts.isEmpty { return }
        let puzzles = try await existing("puzzles", attempts.map(\.puzzleId))
        let runIds = attempts.compactMap(\.runId).filter { !$0.isEmpty }
        let runs = runIds.isEmpty ? Set<String>() : try await existing("runs", runIds)
        let rows = attempts.filter { puzzles.contains($0.puzzleId) }.map { attempt in
            var attempt = attempt
            if let id = attempt.runId, !id.isEmpty, !runs.contains(id) { attempt.runId = nil }
            return attemptRow(attempt)
        }
        for chunk in dataChunks(rows) {
            _ = try await rest.insert("attempts", chunk, UpsertOptions(onConflict: ["id"], ignoreDuplicates: true))
        }
    }
    func resetProgress() async throws {
        let own: [Filter] = [.eq("user_id", .string(userId))]
        try await rest.delete("attempts", own); try await rest.delete("runs", own)
    }
    func createGameCollections(_ collections: [GameCollection]) async throws {
        if collections.isEmpty { return }
        _ = try await rest.insert("game_collections", collections.map {
            ["id": .string($0.id), "name": .string($0.name), "created_at": .string(isoTime($0.createdAt))]
        })
    }
    func renameGameCollection(_ id: String, _ name: String) async throws {
        try await rest.update("game_collections", ["name": .string(name)], [.eq("id", .string(id))])
    }
    func deleteGameCollection(_ id: String) async throws { try await rest.delete("game_collections", [.eq("id", .string(id))]) }
    func addGames(_ games: [NewGame]) async throws {
        for chunk in dataChunks(games) {
            _ = try await rest.insert("games", chunk.map {
                ["id": .string($0.id), "collection_id": .string($0.collectionId), "position": .number(Double($0.position)),
                 "pgn": .string($0.pgn), "orientation": .string($0.orientation.rawValue)]
            })
        }
    }
    func updateGame(_ id: String, _ changes: GameChanges) async throws {
        var patch: Row = [:]
        if let pgn = changes.pgn { patch["pgn"] = .string(pgn) }
        if let orientation = changes.orientation { patch["orientation"] = .string(orientation.rawValue) }
        if patch.isEmpty { return }
        try await rest.update("games", patch, [.eq("id", .string(id))])
    }
    func placeGames(_ placements: [GamePlacement]) async throws {
        for p in placements {
            try await rest.update("games", ["collection_id": .string(p.collectionId), "position": .number(Double(p.position))], [.eq("id", .string(p.id))])
        }
    }
    func deleteGames(_ ids: [String]) async throws {
        for chunk in dataChunks(ids) { try await rest.delete("games", [.in("id", chunk.map(JSONValue.string))]) }
    }
}
