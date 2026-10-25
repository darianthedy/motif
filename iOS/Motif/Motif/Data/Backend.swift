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

/// The account's puzzle library. P04 adds game types; P05 adds backend behavior.
struct Library: Equatable, Codable, Sendable {
    var collections: [Collection] = []
    var puzzles: [Puzzle] = []
    var runs: [Run] = []
    var attempts: [Attempt] = []
}

func emptyLibrary() -> Library { Library() }
