import Foundation

struct OutboxRecords: Equatable, Codable, Sendable {
    var runs: [Run] = []
    var attempts: [Attempt] = []
    var scanRuns: [Run] = []
    var scanAttempts: [ScanAttempt] = []
    var count: Int { runs.count + attempts.count + scanRuns.count + scanAttempts.count }

    init(runs: [Run] = [], attempts: [Attempt] = [], scanRuns: [Run] = [], scanAttempts: [ScanAttempt] = []) {
        self.runs = runs; self.attempts = attempts; self.scanRuns = scanRuns; self.scanAttempts = scanAttempts
    }

    private enum CodingKeys: String, CodingKey { case runs, attempts, scanRuns, scanAttempts }

    /// An outbox written before Scan Training has no scan keys; its play must still upload.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runs = try c.decodeIfPresent([Run].self, forKey: .runs) ?? []
        attempts = try c.decodeIfPresent([Attempt].self, forKey: .attempts) ?? []
        scanRuns = try c.decodeIfPresent([Run].self, forKey: .scanRuns) ?? []
        scanAttempts = try c.decodeIfPresent([ScanAttempt].self, forKey: .scanAttempts) ?? []
    }

    static func + (a: OutboxRecords, b: OutboxRecords) -> OutboxRecords {
        OutboxRecords(runs: a.runs + b.runs, attempts: a.attempts + b.attempts,
                      scanRuns: a.scanRuns + b.scanRuns, scanAttempts: a.scanAttempts + b.scanAttempts)
    }

    /// Less the records in `uploaded`, by id.
    func removing(_ uploaded: OutboxRecords) -> OutboxRecords {
        let runIds = Set(uploaded.runs.map(\.id)), attemptIds = Set(uploaded.attempts.map(\.id))
        let scanRunIds = Set(uploaded.scanRuns.map(\.id)), scanAttemptIds = Set(uploaded.scanAttempts.map(\.id))
        return OutboxRecords(runs: runs.filter { !runIds.contains($0.id) },
                             attempts: attempts.filter { !attemptIds.contains($0.id) },
                             scanRuns: scanRuns.filter { !scanRunIds.contains($0.id) },
                             scanAttempts: scanAttempts.filter { !scanAttemptIds.contains($0.id) })
    }
}
struct OutboxFlush: Sendable {
    var uploaded: OutboxRecords
    var outbox: OutboxRecords
}
/// Only runs and attempts work offline. Immutable ids make repeat uploads
/// safe. Mutations are atomic read/modify/write; in-flight additions survive.
actor Outbox {
    let storage: StoragePaths
    private var flushing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(storage: StoragePaths = StoragePaths()) { self.storage = storage }
    func read(_ userId: String) throws -> OutboxRecords {
        let url = storage.file(userId, "outbox.json")
        if !FileManager.default.fileExists(atPath: url.path) { return OutboxRecords() }
        return try JSONDecoder().decode(OutboxRecords.self, from: Data(contentsOf: url))
    }
    private func save(_ userId: String, _ records: OutboxRecords) throws {
        let url = storage.file(userId, "outbox.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
    }
    func add(_ userId: String, _ added: OutboxRecords) throws {
        try save(userId, try read(userId) + added)
    }
    private func lockFlush() async {
        if flushing { await withCheckedContinuation { waiters.append($0) } }
        else { flushing = true }
    }
    private func unlockFlush() {
        if waiters.isEmpty { flushing = false }
        else { waiters.removeFirst().resume() }
    }
    func flush(_ userId: String, _ backend: any Backend) async throws -> OutboxFlush {
        await lockFlush()
        defer { unlockFlush() }
        let pending = try read(userId)
        for run in pending.runs { try await backend.saveRun(run) }
        try await backend.recordAttempts(pending.attempts)
        for run in pending.scanRuns { try await backend.saveScanRun(run) }
        if !pending.scanAttempts.isEmpty { try await backend.recordScanAttempts(pending.scanAttempts) }
        let current = try read(userId).removing(pending)
        try save(userId, current)
        return OutboxFlush(uploaded: pending, outbox: current)
    }
}

/// Overlay play on the latest server copy. A newer pending run replaces the
/// older scope; attempts are shown once and only for puzzles still present.
func overlay(_ library: Library, _ outbox: OutboxRecords) -> Library {
    if outbox.count == 0 { return library }
    var shown = library
    shown.runs = overlaid(library.runs, outbox.runs)
    shown.scanRuns = overlaid(library.scanRuns, outbox.scanRuns)
    shown.attempts += unseen(outbox.attempts, library.attempts, Set(library.puzzles.map(\.id)))
    shown.scanAttempts += unseen(outbox.scanAttempts, library.scanAttempts, Set(library.scanPuzzles.map(\.id)))
    return shown
}

private func overlaid(_ held: [Run], _ pending: [Run]) -> [Run] {
    var runs = held
    for run in pending {
        if let kept = runs.first(where: { $0.scope == run.scope }), kept.startedAt >= run.startedAt { continue }
        runs.removeAll { $0.scope == run.scope }; runs.append(run)
    }
    return runs
}

private func unseen<A: RunAttempt>(_ pending: [A], _ stored: [A], _ puzzles: Set<String>) -> [A] {
    let storedIds = Set(stored.map(\.id))
    return pending.filter { puzzles.contains($0.puzzleId) && !storedIds.contains($0.id) }
}
