import Foundation

/// The Tactic / Quiet call compared with the maker's.
enum ScanFlagGrade: Equatable, Sendable {
    case pass
    /// Quiet on a tactical position.
    case fail
    /// Tactic on a quiet position.
    case softMiss
}
