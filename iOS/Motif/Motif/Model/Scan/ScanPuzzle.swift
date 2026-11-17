import Foundation

/// A stored scan puzzle: a row of `scan_puzzles`. Everything but the id and
/// time is the maker's, so a re-sent puzzle replaces `content` and keeps both.
struct ScanPuzzle: Equatable, Codable, Sendable {
    var id: String
    var content: ScanPuzzleContent
    var addedAt: Int64

    var fenBefore: String { content.fenBefore }
    var lastMove: Uci { content.lastMove }
    var answer: ScanAnswer { content.answer }
    /// The position the solver scans: `fenBefore` with `lastMove` played.
    /// Non-nil for every stored puzzle, since storing checks it.
    var startFen: String? { content.startFen }
    var contentKey: String { content.contentKey }
}
