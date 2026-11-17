import Foundation

/// The Flag / No Flag call compared with the maker's.
enum ScanFlagGrade: Equatable, Sendable {
    case pass
    /// No Flag on a flagged position.
    case fail
    /// Flag on a quiet position.
    case softMiss
}
