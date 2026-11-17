import Foundation

/// A move compared with the maker's scores.
struct ScanMoveGrade: Equatable, Sendable {
    var passed: Bool
    /// Nil only for a move the maker didn't score, which import rules out.
    var lossCp: Int?
}
