/// Nothing here is stored. Attempts are the only record, so status, counts,
/// review and progress cannot disagree or drift between devices.

/// Oldest first; id breaks ties consistently on every device.
private func chronological(_ attempts: [Attempt]) -> [Attempt] {
    attempts.sorted { $0.playedAt == $1.playedAt ? $0.id < $1.id : $0.playedAt < $1.playedAt }
}

struct PuzzleRecord: Equatable, Codable, Sendable {
    /// Latest non-skip result.
    var status: PuzzleStatus
    /// Played attempts, skips excluded.
    var attempts: Int
    var mistakes: Int
    /// Last served time, skips included.
    var lastPlayedAt: Int64
}

func puzzleRecords(_ attempts: [Attempt]) -> [String: PuzzleRecord] {
    var records: [String: PuzzleRecord] = [:]
    for attempt in chronological(attempts) {
        var record = records[attempt.puzzleId]
            ?? PuzzleRecord(status: .unseen, attempts: 0, mistakes: 0, lastPlayedAt: attempt.playedAt)
        record.lastPlayedAt = attempt.playedAt
        if attempt.result != .skipped {
            record.status = attempt.result == .solved ? .solved : .failed
            record.attempts += 1
            record.mistakes += attempt.mistakes
        }
        records[attempt.puzzleId] = record
    }
    return records
}

func statusOf(_ records: [String: PuzzleRecord], _ puzzleId: String) -> PuzzleStatus {
    records[puzzleId]?.status ?? .unseen
}

/// Latest failures, retaining the supplied puzzle order.
func reviewIds(_ puzzleIds: [String], _ records: [String: PuzzleRecord]) -> [String] {
    puzzleIds.filter { statusOf(records, $0) == .failed }
}

func recentIds(_ attempts: [Attempt]) -> [String] {
    puzzleRecords(attempts).sorted {
        $0.value.lastPlayedAt == $1.value.lastPlayedAt
            ? $0.key < $1.key : $0.value.lastPlayedAt > $1.value.lastPlayedAt
    }.prefix(RECENT_MEMORY).map(\.key)
}

struct Stats: Equatable, Codable, Sendable {
    var total: Int
    var solved: Int
    var failed: Int
    var unseen: Int
}

func statsFor(_ puzzleIds: [String], _ records: [String: PuzzleRecord]) -> Stats {
    var stats = Stats(total: puzzleIds.count, solved: 0, failed: 0, unseen: 0)
    for id in puzzleIds {
        switch statusOf(records, id) {
        case .solved: stats.solved += 1
        case .failed: stats.failed += 1
        case .unseen: stats.unseen += 1
        }
    }
    return stats
}

struct RunProgress: Equatable, Codable, Sendable {
    /// Original queue less deleted puzzles.
    var queue: [String]
    var current: String?
    /// Still to serve, including current and retries.
    var remaining: Int
    /// All attempts in the run, including skips and duplicate device plays.
    var played: Int
    var solved: Int
    /// Ever failed here, even if later retried cleanly.
    var failed: Int
    /// Solved / queue length: retries never reverse the bar.
    var progress: Double
}

private struct Retry {
    var puzzleId: String
    var readyAt: Int
}

/// Replay attempts. Misses return once after the gap, bounded by MAX_RETRIES.
/// Due retries precede fresh puzzles; remaining retries serve early at the end.
/// Concurrent devices interleave; the worst case is a puzzle served twice.
func runProgress(_ run: Run, _ attempts: [Attempt], _ existing: Set<String>) -> RunProgress {
    let queue = run.queue.filter { existing.contains($0) }
    let inQueue = Set(queue)
    let mine = chronological(attempts.filter { $0.runId == run.id && inQueue.contains($0.puzzleId) })
    var finished: Set<String> = []
    var solved: Set<String> = []
    var failed: Set<String> = []
    var retries: [Retry] = []
    var completed = 0
    for attempt in mine {
        let id = attempt.puzzleId
        if finished.contains(id) { continue }
        let retrying = retries.contains { $0.puzzleId == id }
        retries.removeAll { $0.puzzleId == id }
        if attempt.result == .skipped {
            finished.insert(id)
            continue
        }
        completed += 1
        if attempt.result == .solved {
            solved.insert(id)
            finished.insert(id)
        } else {
            failed.insert(id)
            if !retrying && retries.count < MAX_RETRIES {
                retries.append(Retry(puzzleId: id, readyAt: completed + RETRY_GAP))
            } else {
                finished.insert(id)
            }
        }
    }
    let waiting = Set(retries.map(\.puzzleId))
    let fresh = queue.filter { !finished.contains($0) && !waiting.contains($0) }
    let due = retries.first { $0.readyAt <= completed }
    let current = due?.puzzleId ?? fresh.first ?? retries.first?.puzzleId
    return RunProgress(queue: queue, current: current, remaining: fresh.count + retries.count,
                       played: mine.count, solved: solved.count, failed: failed.count,
                       progress: queue.isEmpty ? 1 : min(1, Double(solved.count) / Double(queue.count)))
}
