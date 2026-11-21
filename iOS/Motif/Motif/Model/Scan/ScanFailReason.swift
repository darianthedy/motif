import Foundation

/// Why a scan puzzle failed (Scoring: wrong move, or Quiet on a tactical position).
enum ScanFailReason: String, Codable, CaseIterable, Sendable {
    /// Called Quiet on a tactical position.
    case missedFlag
    /// The move gave away more than the margin.
    case badMove
    /// Time ran out before a move was played.
    case noMove
    /// The quick scan's limit ran out before Tactic or Quiet: a fail on any position.
    case noCall
    /// A later move of the line (v7) left every line the puzzle has.
    case offLine
}
