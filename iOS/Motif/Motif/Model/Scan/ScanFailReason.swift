import Foundation

/// Why a scan puzzle failed (Scoring: wrong move, or No Flag on a flagged position).
enum ScanFailReason: String, Codable, CaseIterable, Sendable {
    /// Called No Flag on a flagged position.
    case missedFlag
    /// The move gave away more than the margin.
    case badMove
    /// Time ran out before a move was played.
    case noMove
}
