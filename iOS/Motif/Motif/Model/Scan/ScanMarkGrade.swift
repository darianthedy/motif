import Foundation

/// Marks compared with the answer.
struct ScanMarkGrade: Equatable, Sendable {
    /// In the answer's order.
    var missed: [String] = []
    /// Sorted.
    var extra: [String] = []
}
