import Foundation

/// What progress, review and resume read from an attempt. Puzzle and scan
/// attempts both adopt it, so `Derive.swift` serves both tabs with one copy.
protocol RunAttempt {
    /// Made on the device; breaks ties between attempts played at the same time.
    var id: String { get }
    var puzzleId: String { get }
    /// Nil once the run it belonged to is gone.
    var runId: String? { get }
    var result: AttemptResult { get }
    var playedAt: Int64 { get }
    /// Counted into `PuzzleRecord.mistakes`.
    var mistakes: Int { get }
    /// Leaves the puzzle in To review (`PuzzleRecord.status` failed) once it's the latest.
    var needsReview: Bool { get }
}

extension RunAttempt {
    var needsReview: Bool { result == .failed }
}

extension Attempt: RunAttempt {}
