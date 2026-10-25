import Foundation
@testable import Motif

func testStorage() -> StoragePaths {
    StoragePaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("MotifTests-" + newID()))
}
func testDataLibrary() -> Library {
    Library(collections: [Collection(id: "c1", name: "C", createdAt: 0)],
            puzzles: [testPuzzle([["a1a8"]])])
}
func testDataRun(_ scope: String = "c1", _ time: Int64 = 5) -> Run {
    Run(id: "\(scope)-\(time)", scope: scope, mode: .ordered, queue: ["p1"], startedAt: time)
}
func testDataAttempt(_ id: String = "a1", puzzleId: String = "p1") -> Attempt {
    Attempt(id: id, puzzleId: puzzleId, runId: nil, result: .solved, mistakes: 0, hinted: false, playedAt: 1)
}

actor DataEvents {
    private(set) var events: [String] = []
    private var observed: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var gate: CheckedContinuation<Void, Never>?
    var pauseSave = false
    var failAttempts = false
    func setPause(_ pause: Bool) { pauseSave = pause }
    func setFail(_ fail: Bool) { failAttempts = fail }
    func record(_ event: String) async {
        events.append(event)
        for waiter in observed.removeValue(forKey: event) ?? [] { waiter.resume() }
        if event == "save", pauseSave { await withCheckedContinuation { gate = $0 } }
    }
    func waitFor(_ event: String) async {
        if events.contains(event) { return }
        await withCheckedContinuation { observed[event, default: []].append($0) }
    }
    func release() { pauseSave = false; gate?.resume(); gate = nil }
}

struct LoggingBackend: Backend {
    let memory: MemoryBackend
    let events: DataEvents
    init(_ initial: Library = testDataLibrary(), events: DataEvents = DataEvents()) {
        memory = MemoryBackend(initial); self.events = events
    }
    func load() async throws -> Library { await events.record("load"); return await memory.load() }
    func createCollections(_ c: [Collection]) async throws { try await memory.createCollections(c) }
    func renameCollection(_ id: String, _ name: String) async throws { try await memory.renameCollection(id, name) }
    func deleteCollection(_ id: String) async throws { try await memory.deleteCollection(id) }
    func importPuzzles(_ p: [NewPuzzle]) async throws -> [Puzzle] { try await memory.importPuzzles(p) }
    func setComment(_ id: String, _ text: String) async throws { try await memory.setComment(id, text) }
    func setFlagged(_ id: String, _ flag: Bool) async throws { try await memory.setFlagged(id, flag) }
    func deletePuzzle(_ id: String) async throws { try await memory.deletePuzzle(id) }
    func saveRun(_ r: Run) async throws { await events.record("save"); try await memory.saveRun(r) }
    func deleteRun(_ id: String) async throws { try await memory.deleteRun(id) }
    func recordAttempts(_ a: [Attempt]) async throws {
        await events.record("attempts")
        if await events.failAttempts { throw DataFailure(message: "Upload failed") }
        try await memory.recordAttempts(a)
    }
    func resetProgress() async throws { await events.record("reset"); try await memory.resetProgress() }
    func createGameCollections(_ c: [GameCollection]) async throws { try await memory.createGameCollections(c) }
    func renameGameCollection(_ id: String, _ name: String) async throws { try await memory.renameGameCollection(id, name) }
    func deleteGameCollection(_ id: String) async throws { try await memory.deleteGameCollection(id) }
    func addGames(_ g: [NewGame]) async throws { try await memory.addGames(g) }
    func updateGame(_ id: String, _ changes: GameChanges) async throws { try await memory.updateGame(id, changes) }
    func placeGames(_ p: [GamePlacement]) async throws { try await memory.placeGames(p) }
    func deleteGames(_ ids: [String]) async throws { try await memory.deleteGames(ids) }
}
actor TestAccount: Account {
    private var user: User?
    let held: any Backend
    init(_ user: User?, _ backend: any Backend) { self.user = user; held = backend }
    func currentUser() -> User? { user }
    func signIn(_ email: String, _ password: String) { user = User(id: email, email: email) }
    func signUp(_ email: String, _ password: String) { signIn(email, password) }
    func signOut() { user = nil }
    func backend(_ user: User) -> any Backend { held }
}
