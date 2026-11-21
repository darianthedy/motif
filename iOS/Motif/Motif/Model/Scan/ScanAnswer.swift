import Foundation

/// The maker's answer to one scan puzzle, stored as `scan_puzzles.answer`.
/// Motif never works any of it out; it only compares input with it.
struct ScanAnswer: Equatable, Codable, Sendable {
    /// What the position is: Tactic or Quiet. Not `Puzzle.flagged`, which
    /// means "needs a look".
    var flagged: Bool
    var quickScan: [ScanSquare]
    /// Checks, captures and threats for the full scan; present on a Tactic puzzle from v2. There are
    /// no targets: the graded target step went in v6, and an older row's `targets` is ignored.
    var arrows: [ScanArrow]?
    /// Every legal move of the solver, keyed by UCI, with how many centipawns
    /// worse it is than the best (best = 0, a thrown-away mate = 100000).
    var moves: [String: Int]
    var bestLine: [Uci]?
    /// The line to play out (v7, Tactic puzzles only): one or more lines of UCI moves for both
    /// sides, each starting with the solver's first move, as a normal puzzle's `solutions`. Nil
    /// for a one-move puzzle.
    var solutions: [[Uci]]? = nil
    /// The best move's eval in centipawns from the solver's side (v7; a forced mate = 100000),
    /// so a clearly winning position is graded by win chance lost. Nil before v7.
    var bestCp: Int? = nil

    /// Whether the Tactic branch runs the full scan (CCT arrows, then the move and final check).
    /// Version 2 on requires arrows on a Tactic puzzle; a version 1 Tactic puzzle without them goes
    /// straight to the move.
    var hasFullScan: Bool { flagged && arrows != nil }

    /// Whether the move is played out past the first move (v7).
    var hasLine: Bool { !(solutions ?? []).isEmpty }

    /// A thrown-away forced mate, as the maker scores it; also `bestCp` for a forced mate.
    static let lostMateCp = 100_000

    /// The centipawn loss of a move, or nil when it isn't listed.
    func lossCp(_ move: Uci) -> Int? { moves[move.text] }
}
