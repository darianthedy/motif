import Foundation

/// One finished scan puzzle: a row of `scan_attempts`, only ever inserted.
struct ScanAttempt: Equatable, Codable, Sendable, RunAttempt {
    /// Device-generated id makes repeat uploads idempotent.
    var id: String
    var puzzleId: String
    /// Nil once the run it belonged to is gone.
    var runId: String?
    /// `solved` = passed, as for puzzles, so the derive code serves both.
    var result: AttemptResult
    /// What the user called: Flag (true) or No Flag. Nil for a skip.
    var flagCall: Bool?
    var detail: ScanAttemptDetail
    var playedAt: Int64

    /// A failed scan is one mistake; soft misses aren't mistakes.
    var mistakes: Int { result == .failed ? 1 : 0 }

    init(id: String = newID(), puzzleId: String, runId: String?, result: AttemptResult,
         flagCall: Bool?, detail: ScanAttemptDetail, playedAt: Int64) {
        self.id = id; self.puzzleId = puzzleId; self.runId = runId; self.result = result
        self.flagCall = flagCall; self.detail = detail; self.playedAt = playedAt
    }

    /// A graded puzzle, from `ScanGrader.result(of:flagCall:answer:)`.
    init(id: String = newID(), puzzleId: String, runId: String?, flagCall: Bool,
         outcome: ScanOutcome, playedAt: Int64) {
        self.init(id: id, puzzleId: puzzleId, runId: runId, result: outcome.result,
                  flagCall: flagCall, detail: outcome.detail, playedAt: playedAt)
    }

    /// A skipped puzzle: doesn't come back this run and counts as neither.
    static func skip(id: String = newID(), puzzleId: String, runId: String?, playedAt: Int64) -> ScanAttempt {
        ScanAttempt(id: id, puzzleId: puzzleId, runId: runId, result: .skipped,
                    flagCall: nil, detail: ScanAttemptDetail(), playedAt: playedAt)
    }
}
