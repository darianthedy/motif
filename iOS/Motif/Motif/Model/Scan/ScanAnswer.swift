import Foundation

/// The maker's answer to one scan puzzle, stored as `scan_puzzles.answer`.
/// Motif never works any of it out; it only compares input with it.
struct ScanAnswer: Equatable, Codable, Sendable {
    /// What the position is: Flag or No flag. Not `Puzzle.flagged`, which
    /// means "needs a look".
    var flagged: Bool
    var quickScan: [ScanSquare]
    var targets: ScanTargets?
    var arrows: [ScanArrow]?
    /// Every legal move of the solver, keyed by UCI, with how many centipawns
    /// worse it is than the best (best = 0, a thrown-away mate = 100000).
    var moves: [String: Int]
    var bestLine: [Uci]?

    /// A thrown-away forced mate, as the maker scores it.
    static let lostMateCp = 100_000

    /// The centipawn loss of a move, or nil when it isn't listed.
    func lossCp(_ move: Uci) -> Int? { moves[move.text] }
}
