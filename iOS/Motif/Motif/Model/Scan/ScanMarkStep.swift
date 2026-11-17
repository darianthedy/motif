import Foundation

/// A step that marks the board: what it took and what it got wrong.
struct ScanMarkStep: Equatable, Codable, Sendable {
    var ms: Int
    /// The hard limit in force; nil while timing is record-only.
    var limitMs: Int?
    /// Squares (or arrows, "f3g5") the answer has that weren't marked.
    var missed: [String] = []
    /// Marked but not in the answer. Recorded, never counted against.
    var extra: [String] = []
    /// The limit ran out and the step ended as it stood; nil when it was finished in time. A
    /// quick scan that ran out had no call, and fails the puzzle (`ScanFailReason.noCall`).
    var timedOut: Bool? = nil
}
