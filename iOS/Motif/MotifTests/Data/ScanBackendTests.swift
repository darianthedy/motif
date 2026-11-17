import XCTest
@testable import Motif

/// The scan cases, each run against memory and RestBackend, as BackendSuiteTests.
final class ScanBackendTests: XCTestCase {
    private func each(_ run: (any Backend) async throws -> Void) async throws {
        let backends: [any Backend] = [MemoryBackend(), RestBackend(rest: MemoryRest(), userId: "test")]
        for backend in backends { try await run(backend) }
    }
    private func seeded(_ b: any Backend, _ moves: [String] = ["e1d1", "e1f1"]) async throws -> [ScanPuzzle] {
        try await b.importScanPuzzles(moves.map { testScanContent($0) })
    }
    private func run(_ scope: String, _ queue: [String], _ time: Int64 = 2000) -> Run {
        Run(id: newID(), scope: scope, mode: scope == SCOPE_REVIEW ? .reviewMistakes : .randomGlobal, queue: queue, startedAt: time)
    }
    private func attempt(_ puzzleId: String, runId: String? = nil, _ result: AttemptResult = .solved) -> ScanAttempt {
        let steps = ScanSteps(quickScan: ScanMarkStep(ms: 7400, missed: ["c6"]),
                              move: ScanMoveStep(ms: 3100, played: Uci.parse("e8e7"), lossCp: 0))
        return ScanAttempt(puzzleId: puzzleId, runId: runId, result: result, flagCall: false,
                           detail: ScanAttemptDetail(steps: steps, softMisses: [.quickScanMissed]), playedAt: 3000)
    }

    func testStoresAndLoadsEveryKindOfScanRow() async throws {
        try await each { b in
            var content = testScanContent("e1d1", source: "lichess"); content.sourceId = "00sHx"
            content.answer.bestLine = [Uci.parse("e8e7")!]
            let p = try await b.importScanPuzzles([content])[0]
            let r = self.run(SCOPE_ALL, [p.id]); try await b.saveScanRun(r)
            let a = self.attempt(p.id, runId: r.id, .failed); try await b.recordScanAttempts([a])
            let lib = try await b.load()
            XCTAssertEqual(lib.scanPuzzles, [p]); XCTAssertEqual(lib.scanPuzzles[0].content, content)
            XCTAssertEqual(lib.scanPuzzles[0].startFen, "4k3/8/8/8/8/8/8/3K4 b - - 1 1")
            XCTAssertEqual(lib.scanRuns, [r]); XCTAssertEqual(lib.scanAttempts, [a])
            XCTAssertEqual(lib.runs, []); XCTAssertEqual(lib.attempts, [])
        }
    }
    func testReSendingAPuzzleUpdatesItAndKeepsItsProgress() async throws {
        try await each { b in
            let first = try await self.seeded(b, ["e1d1"])[0]
            try await b.recordScanAttempts([self.attempt(first.id)])
            var changed = testScanContent("e1d1", flagged: false); changed.fenBefore = "4k3/8/8/8/8/8/8/4K3 w - - 7 30"
            let again = try await b.importScanPuzzles([changed])[0]
            XCTAssertEqual(again.id, first.id); XCTAssertEqual(again.addedAt, first.addedAt)
            let lib = try await b.load()
            XCTAssertEqual(lib.scanPuzzles.count, 1); XCTAssertEqual(lib.scanPuzzles[0].answer.flagged, false)
            XCTAssertEqual(lib.scanAttempts.count, 1)
        }
    }
    func testKeepsOnePuzzleListedTwiceInAnImport() async throws {
        try await each { b in
            let stored = try await b.importScanPuzzles([testScanContent(flagged: true), testScanContent(flagged: false)])
            XCTAssertEqual(stored.count, 1)
            let lib = try await b.load(); XCTAssertEqual(lib.scanPuzzles.map(\.answer.flagged), [false])
        }
    }
    func testDeletesAPuzzleWithItsAttempts() async throws {
        try await each { b in
            let p = try await self.seeded(b); try await b.recordScanAttempts(p.map { self.attempt($0.id) })
            try await b.deleteScanPuzzle(p[0].id)
            let lib = try await b.load()
            XCTAssertEqual(lib.scanPuzzles.map(\.id), [p[1].id]); XCTAssertEqual(lib.scanAttempts.map(\.puzzleId), [p[1].id])
        }
    }
    func testStoresAnAttemptUploadedTwiceOnce() async throws {
        try await each { b in
            let p = try await self.seeded(b, ["e1d1"]); let a = self.attempt(p[0].id); var changed = a; changed.result = .failed
            try await b.recordScanAttempts([a]); try await b.recordScanAttempts([a, changed])
            let lib = try await b.load(); XCTAssertEqual(lib.scanAttempts, [a])
        }
    }
    func testDropsDeletedPuzzleAttemptsAndUnlinksDeletedRuns() async throws {
        try await each { b in
            let p = try await self.seeded(b), r = self.run(SCOPE_ALL, [])
            try await b.deleteScanPuzzle(p[0].id); try await b.recordScanAttempts(p.map { self.attempt($0.id, runId: r.id) })
            let lib = try await b.load()
            XCTAssertEqual(lib.scanAttempts.map(\.puzzleId), [p[1].id]); XCTAssertNil(lib.scanAttempts[0].runId)
        }
    }
    func testKeepsTheNewestRunPerScopeAndDeletesARunKeepingItsAttempts() async throws {
        try await each { b in
            let p = try await self.seeded(b, ["e1d1"])
            let first = self.run(SCOPE_ALL, [p[0].id], 1000), second = self.run(SCOPE_ALL, [p[0].id], 2000)
            let stale = self.run(SCOPE_ALL, [p[0].id], 1500), review = self.run(SCOPE_REVIEW, [p[0].id])
            try await b.saveScanRun(first); try await b.recordScanAttempts([self.attempt(p[0].id, runId: first.id)])
            try await b.saveScanRun(second); try await b.saveScanRun(stale); try await b.saveScanRun(review)
            var lib = try await b.load()
            XCTAssertEqual(Set(lib.scanRuns.map(\.id)), [second.id, review.id]); XCTAssertNil(lib.scanAttempts[0].runId)
            try await b.recordScanAttempts([self.attempt(p[0].id, runId: review.id)]); try await b.deleteScanRun(review.id)
            lib = try await b.load()
            XCTAssertEqual(lib.scanRuns, [second]); XCTAssertEqual(lib.scanAttempts.count, 2)
            XCTAssertTrue(lib.scanAttempts.allSatisfy { $0.runId == nil })
        }
    }
    func testScanAndPuzzleResetsLeaveEachOtherAlone() async throws {
        try await each { b in
            let c = Collection(id: newID(), name: "C", createdAt: 1); try await b.createCollections([c])
            let puzzle = try await b.importPuzzles([NewPuzzle(testContent([["a1a8"]]), collectionId: c.id, position: 0)])[0]
            let puzzleRun = Run(id: newID(), scope: SCOPE_ALL, mode: .randomGlobal, queue: [puzzle.id], startedAt: 1)
            try await b.saveRun(puzzleRun)
            try await b.recordAttempts([Attempt(id: newID(), puzzleId: puzzle.id, runId: puzzleRun.id, result: .solved,
                                                mistakes: 0, hinted: false, playedAt: 2)])
            let p = try await self.seeded(b), r = self.run(SCOPE_ALL, p.map(\.id))
            try await b.saveScanRun(r); try await b.recordScanAttempts(p.map { self.attempt($0.id, runId: r.id) })

            try await b.resetScanProgress()
            var lib = try await b.load()
            XCTAssertEqual(lib.scanAttempts, []); XCTAssertEqual(lib.scanRuns, []); XCTAssertEqual(lib.scanPuzzles.count, 2)
            XCTAssertEqual(lib.attempts.count, 1); XCTAssertEqual(lib.runs, [puzzleRun])

            try await b.saveScanRun(r); try await b.recordScanAttempts([self.attempt(p[0].id, runId: r.id)])
            try await b.resetProgress()
            lib = try await b.load()
            XCTAssertEqual(lib.attempts, []); XCTAssertEqual(lib.runs, [])
            XCTAssertEqual(lib.scanAttempts.count, 1); XCTAssertEqual(lib.scanRuns, [r])
        }
    }

    // MARK: Rows written straight to the database

    private func directRow(_ id: String, lastMove: String, answer: JSONValue, version: Int = 1) -> Row {
        ["id": .string(id), "content_key": .string("k-\(id)"), "fen_before": .string(scanTestFen),
         "last_move": .string(lastMove), "answer": answer, "version": .number(Double(version)),
         "added_at": .string(isoTime(5000))]
    }

    func testABadRowFromTheDatabaseIsSkippedNotFatal() async throws {
        let rest = MemoryRest(), backend = RestBackend(rest: rest, userId: "test")
        let good = try jsonValue(testScanContent("e1d1").answer)
        var missingMove = testScanContent("e1f1").answer; missingMove.moves.removeValue(forKey: "e8e7")
        _ = try await rest.insert("scan_puzzles", [
            directRow("good", lastMove: "e1d1", answer: good),
            directRow("illegal", lastMove: "e1e3", answer: good),
            directRow("incomplete", lastMove: "e1f1", answer: try jsonValue(missingMove)),
            directRow("newer", lastMove: "e1d1", answer: good, version: ScanImport.version + 1),
            directRow("garbage", lastMove: "e1d1", answer: .string("flagged")),
        ])
        let lib = try await backend.load()
        XCTAssertEqual(lib.scanPuzzles.map(\.id), ["good"])
    }

    func testARowWrittenByTheMakerWithWholeNumbersAsDoublesLoads() async throws {
        let rest = MemoryRest(), backend = RestBackend(rest: rest, userId: "test")
        var moves: [String: JSONValue] = [:]
        for move in Board.legalUcis(Board.applyUci(scanTestFen, Uci.parse("e1d1")!)!) { moves[move.text] = .number(12.0) }
        moves["e8d8"] = .number(0.0)
        let answer: JSONValue = .object(["flagged": .bool(false), "quickScan": .array([]), "moves": .object(moves)])
        _ = try await rest.insert("scan_puzzles", [directRow("maker", lastMove: "e1d1", answer: answer)])
        let lib = try await backend.load()
        XCTAssertEqual(lib.scanPuzzles.first?.answer.lossCp(Uci.parse("e8e7")!), 12)
    }
}
