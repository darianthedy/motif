import XCTest
@testable import Motif

final class ScanOutboxTests: XCTestCase {
    private func library() -> Library {
        var lib = testDataLibrary(); lib.scanPuzzles = [testScanPuzzle("s1")]; return lib
    }

    func testOverlaysScanRunsAndAttemptsLikePuzzleOnes() {
        var base = library(); base.scanRuns = [testScanRun(SCOPE_ALL, 5)]; base.scanAttempts = [testScanAttempt("a1", "s1")]
        let shown = overlay(base, OutboxRecords(scanRuns: [testScanRun(SCOPE_ALL, 9), testScanRun(SCOPE_REVIEW, 1)],
                                                scanAttempts: [testScanAttempt("a1", "s1"), testScanAttempt("a2", "s1"),
                                                               testScanAttempt("a3", "gone")]))
        XCTAssertEqual(shown.scanRuns.map(\.id).sorted(), ["scan-all-9", "scan-review-1"])
        XCTAssertEqual(shown.scanAttempts.map(\.id), ["a1", "a2"])
        XCTAssertEqual(shown.runs, base.runs); XCTAssertEqual(shown.attempts, base.attempts)
    }

    func testFlushUploadsScanPlayAfterPuzzlePlayAndEmptiesTheOutbox() async throws {
        let storage = testStorage(), box = Outbox(storage: storage), backend = LoggingBackend(library())
        try await box.add("u", OutboxRecords(runs: [testDataRun()], attempts: [testDataAttempt()]))
        try await box.add("u", OutboxRecords(scanRuns: [testScanRun()], scanAttempts: [testScanAttempt("a1", "s1")]))
        let result = try await box.flush("u", backend)
        XCTAssertEqual(result.uploaded.count, 4); XCTAssertEqual(result.outbox.count, 0)
        let events = await backend.events.events
        XCTAssertEqual(events, ["save", "attempts", "scanSave", "scanAttempts"])
        let lib = try await backend.load()
        XCTAssertEqual(lib.scanRuns.count, 1); XCTAssertEqual(lib.scanAttempts.count, 1)
        let persisted = try await Outbox(storage: storage).read("u"); XCTAssertEqual(persisted.count, 0)
    }

    func testAFailedScanUploadKeepsEverythingForRetry() async throws {
        let box = Outbox(storage: testStorage()), backend = LoggingBackend(library())
        await backend.events.setFail(true)
        let pending = OutboxRecords(scanRuns: [testScanRun()], scanAttempts: [testScanAttempt("a1", "s1")])
        try await box.add("u", pending)
        do { _ = try await box.flush("u", backend); XCTFail("Upload did not fail") } catch {}
        let kept = try await box.read("u"); XCTAssertEqual(kept, pending)
    }

    func testAnOutboxAndCacheFromBeforeScanTrainingStillRead() async throws {
        let storage = testStorage()
        let old = #"{"runs":[],"attempts":[{"id":"a1","puzzleId":"p1","result":"solved","mistakes":0,"hinted":false,"playedAt":1}]}"#
        let url = storage.file("u", "outbox.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(old.utf8).write(to: url)
        let records = try await Outbox(storage: storage).read("u")
        XCTAssertEqual(records.attempts.map(\.id), ["a1"]); XCTAssertEqual(records.scanAttempts, [])

        try Data(#"{"collections":[],"puzzles":[]}"#.utf8).write(to: storage.file("u", "library.json"))
        let cached = await Cache(storage: storage).load("u")
        XCTAssertEqual(cached?.scanPuzzles, []); XCTAssertEqual(cached?.scanRuns, [])
    }
}
