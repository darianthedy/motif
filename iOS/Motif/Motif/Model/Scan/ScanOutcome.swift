import Foundation

/// A graded scan, ready to store as a `ScanAttempt`.
struct ScanOutcome: Equatable, Sendable {
    /// `solved` or `failed`.
    var result: AttemptResult
    var detail: ScanAttemptDetail
}
