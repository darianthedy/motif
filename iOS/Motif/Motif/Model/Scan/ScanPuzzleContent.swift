import Foundation

/// A scan puzzle as the maker sends it, checked and ready to store: what an
/// import writes to `scan_puzzles`, before it has an id.
struct ScanPuzzleContent: Equatable, Codable, Sendable {
    /// The position before the opponent's last move.
    var fenBefore: String
    /// The opponent's last move. The solver is the side to move after it.
    var lastMove: Uci
    var answer: ScanAnswer
    /// The format version it was written in.
    var version: Int
    var source: String?
    var sourceId: String?

    /// The position the solver scans: `fenBefore` with `lastMove` played.
    /// Non-nil for anything that passed `ScanImport`.
    var startFen: String? { Board.applyUci(fenBefore, lastMove) }

    /// Position (no move counters) + last move: the same position sent twice
    /// is the same puzzle, so it updates instead of adding a second one.
    var contentKey: String { ScanImport.contentKey(fenBefore: fenBefore, lastMove: lastMove) }
}
