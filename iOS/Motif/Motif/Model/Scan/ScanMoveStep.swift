import Foundation

/// The move step: what was played and how much it gave away.
struct ScanMoveStep: Equatable, Codable, Sendable {
    var ms: Int
    /// The hard limit in force; nil while timing is record-only.
    var limitMs: Int?
    /// Nil when time ran out before a move.
    var played: Uci?
    /// Centipawns worse than the best, from the maker's `moves`.
    var lossCp: Int?
}
