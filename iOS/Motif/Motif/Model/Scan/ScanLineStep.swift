import Foundation

/// Playing the line out after a first move on it (v7): the solver's later moves and their time.
struct ScanLineStep: Equatable, Codable, Sendable {
    /// From the opponent's first reply to the end of the line, or to the move that left it.
    var ms: Int
    /// The solver's moves after the first, in order; when `offLine`, the last one left the line.
    var played: [Uci]
    /// A move left every line: the puzzle fails (Scoring › Line moves). Nil when it didn't.
    var offLine: Bool? = nil
}
