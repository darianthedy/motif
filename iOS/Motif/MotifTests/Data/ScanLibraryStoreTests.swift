import XCTest
@testable import Motif

@MainActor
final class ScanLibraryStoreTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let defaults = UserDefaults(suiteName: "MotifTests." + newID())!
        defaults.set(try JSONEncoder().encode(User(id: "u", email: "e")), forKey: "motif:user")
        return defaults
    }

    /// Plan §10: a run started and played offline is in the outbox, survives a
    /// relaunch, and uploads once on reconnect.
    func testScanPlayOfflineSurvivesARelaunchAndUploadsOnce() async throws {
        let storage = testStorage(), memory = MemoryBackend()
        let puzzle = try await memory.importScanPuzzles([testScanContent()])[0]
        let backend = LoggingBackend(await memory.load())
        let account = TestAccount(User(id: "u", email: "e"), backend), userDefaults = try defaults()
        let store = LibraryStore(account: account, cache: Cache(storage: storage), outbox: Outbox(storage: storage),
                                 defaults: userDefaults)
        await store.open()
        XCTAssertEqual(store.library?.scanPuzzles.map(\.id), [puzzle.id])

        await store.setOnline(false)
        let run = Run(id: newID(), scope: SCOPE_ALL, mode: .randomGlobal, queue: [puzzle.id], startedAt: 10)
        try await store.startScanRun(run)
        try await store.recordScanAttempt(testScanAttempt("a1", puzzle.id, .failed, runId: run.id, playedAt: 11))
        XCTAssertEqual(store.pending, 2)
        XCTAssertEqual(store.library?.scanRuns, [run]); XCTAssertEqual(store.library?.scanAttempts.map(\.id), ["a1"])
        var uploaded = await backend.events.events
        XCTAssertFalse(uploaded.contains("scanAttempts"))

        let relaunched = LibraryStore(account: account, cache: Cache(storage: storage), outbox: Outbox(storage: storage),
                                      defaults: userDefaults, online: false)
        await relaunched.open()
        XCTAssertEqual(relaunched.pending, 2)
        XCTAssertEqual(relaunched.library?.scanPuzzles.map(\.id), [puzzle.id], "the cache holds the pool")
        XCTAssertEqual(relaunched.library.map { scanProgressOf($0, run).failed }, 1)

        await relaunched.setOnline(true)
        XCTAssertEqual(relaunched.pending, 0)
        await relaunched.refresh()
        uploaded = await backend.events.events
        XCTAssertEqual(uploaded.filter { $0 == "scanSave" }.count, 1)
        let server = try await backend.load()
        XCTAssertEqual(server.scanRuns, [run]); XCTAssertEqual(server.scanAttempts.map(\.id), ["a1"])
        XCTAssertEqual(relaunched.library?.scanAttempts.map(\.id), ["a1"])
    }

    func testScanResetFlushesPlayFirstAndLeavesPuzzleProgress() async throws {
        let storage = testStorage(), memory = MemoryBackend(testDataLibrary())
        let puzzle = try await memory.importScanPuzzles([testScanContent()])[0]
        let backend = LoggingBackend(await memory.load())
        let store = LibraryStore(account: TestAccount(User(id: "u", email: "e"), backend), cache: Cache(storage: storage),
                                 outbox: Outbox(storage: storage), defaults: try defaults())
        await store.open()
        store.online = false
        try await store.recordAttempt(testDataAttempt())
        try await store.recordScanAttempt(testScanAttempt("a1", puzzle.id))
        store.online = true
        try await store.write { try await $0.resetScanProgress() }
        XCTAssertEqual(store.library?.scanAttempts, []); XCTAssertEqual(store.library?.attempts.count, 1)
        XCTAssertEqual(store.library?.scanPuzzles.count, 1); XCTAssertEqual(store.pending, 0)
        let events = await backend.events.events
        let reset = try XCTUnwrap(events.firstIndex(of: "scanReset"))
        XCTAssertTrue(events[..<reset].contains("scanAttempts"))
    }
}
