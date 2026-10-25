import Foundation

struct OutboxRecords: Equatable, Codable, Sendable {
    var runs: [Run] = []
    var attempts: [Attempt] = []
    var count: Int { runs.count + attempts.count }
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
        var records = try read(userId)
        records.runs += added.runs; records.attempts += added.attempts
        try save(userId, records)
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
        let runIds = Set(pending.runs.map(\.id)), attemptIds = Set(pending.attempts.map(\.id))
        var current = try read(userId)
        current.runs.removeAll { runIds.contains($0.id) }; current.attempts.removeAll { attemptIds.contains($0.id) }
        try save(userId, current)
        return OutboxFlush(uploaded: pending, outbox: current)
    }
}

/// Overlay play on the latest server copy. A newer pending run replaces the
/// older scope; attempts are shown once and only for puzzles still present.
func overlay(_ library: Library, _ outbox: OutboxRecords) -> Library {
    if outbox.count == 0 { return library }
    var shown = library
    for run in outbox.runs {
        if let held = shown.runs.first(where: { $0.scope == run.scope }), held.startedAt >= run.startedAt { continue }
        shown.runs.removeAll { $0.scope == run.scope }; shown.runs.append(run)
    }
    let puzzles = Set(library.puzzles.map(\.id)), stored = Set(library.attempts.map(\.id))
    shown.attempts += outbox.attempts.filter { puzzles.contains($0.puzzleId) && !stored.contains($0.id) }
    return shown
}
