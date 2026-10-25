import XCTest
@testable import Motif

final class OutboxTests: XCTestCase {
    // The three source outbox.test.ts cases.
    func testReplacesOnlyAnOlderRunInTheSameScope() {
        var base = testDataLibrary(); base.runs = [testDataRun("c1", 5), testDataRun("all", 5)]
        let shown = overlay(base, OutboxRecords(runs: [testDataRun("c1", 9), testDataRun("all", 1)]))
        XCTAssertEqual(shown.runs.map(\.id).sorted(), ["all-5", "c1-9"])
    }
    func testAddsAttemptsOnceAndNotForDeletedPuzzles() {
        var base = testDataLibrary(); base.attempts = [testDataAttempt()]
        let shown = overlay(base, OutboxRecords(attempts: [testDataAttempt(), testDataAttempt("a2"), testDataAttempt("a3", puzzleId: "gone")]))
        XCTAssertEqual(shown.attempts.map(\.id), ["a1", "a2"])
    }
    func testLeavesTheLibraryUnchangedWithNothingWaiting() {
        let base = testDataLibrary(); XCTAssertEqual(overlay(base, OutboxRecords()), base)
    }
    func testRunsUploadBeforeAttemptsAndWaitingRecordsAreDurable() async throws {
        let storage = testStorage(), box = Outbox(storage: storage), backend = LoggingBackend()
        try await box.add("u", OutboxRecords(runs: [testDataRun()], attempts: [testDataAttempt()]))
        let result = try await box.flush("u", backend)
        XCTAssertEqual(result.uploaded.count, 2); XCTAssertEqual(result.outbox.count, 0)
        let events = await backend.events.events; XCTAssertEqual(events, ["save", "attempts"])
        let reopened = Outbox(storage: storage), persisted = try await reopened.read("u")
        XCTAssertEqual(persisted.count, 0)
    }
    func testFailedUploadsKeepAllRecordsForRetry() async throws {
        let box = Outbox(storage: testStorage()), backend = LoggingBackend()
        await backend.events.setFail(true)
        let pending = OutboxRecords(runs: [testDataRun()], attempts: [testDataAttempt()])
        try await box.add("u", pending)
        do { _ = try await box.flush("u", backend); XCTFail("Upload did not fail") } catch {}
        let kept = try await box.read("u"); XCTAssertEqual(kept, pending)
        await backend.events.setFail(false)
        _ = try await box.flush("u", backend)
        let library = try await backend.load()
        XCTAssertEqual(library.runs.count, 1); XCTAssertEqual(library.attempts.count, 1)
    }
    func testAdditionsDuringAnUploadSurviveForNextFlush() async throws {
        let box = Outbox(storage: testStorage()), backend = LoggingBackend()
        await backend.events.setPause(true)
        try await box.add("u", OutboxRecords(runs: [testDataRun()]))
        let flushing = Task { try await box.flush("u", backend) }
        await backend.events.waitFor("save")
        try await box.add("u", OutboxRecords(attempts: [testDataAttempt("late")]))
        await backend.events.release()
        let result = try await flushing.value
        XCTAssertEqual(result.outbox.attempts.map(\.id), ["late"])
        _ = try await box.flush("u", backend)
        let library = try await backend.load(); XCTAssertEqual(library.attempts.map(\.id), ["late"])
    }
    func testConcurrentFlushesSerializeAndConcurrentAddsNeverLoseRecords() async throws {
        let box = Outbox(storage: testStorage()), backend = LoggingBackend()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 { group.addTask { try await box.add("u", OutboxRecords(attempts: [testDataAttempt("a\(i)")])) } }
            try await group.waitForAll()
        }
        let before = try await box.read("u"); XCTAssertEqual(before.count, 100)
        async let first = box.flush("u", backend); async let second = box.flush("u", backend)
        _ = try await (first, second)
        let after = try await box.read("u"); XCTAssertEqual(after.count, 0)
        let library = try await backend.load(); XCTAssertEqual(library.attempts.count, 100)
    }
    func testUnreadableOutboxThrowsRatherThanDiscardingUnsyncedPlay() async throws {
        let storage = testStorage(), url = storage.file("u", "outbox.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("bad".utf8).write(to: url)
        do { _ = try await Outbox(storage: storage).read("u"); XCTFail("Discarded unreadable outbox") } catch {}
    }
}
