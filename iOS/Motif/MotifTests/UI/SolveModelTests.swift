import XCTest
@testable import Motif

@MainActor final class SolveModelTests: XCTestCase {
    private func waitUntil(_ check: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 { if check() { return }; await Task.yield() }
        XCTFail("State did not settle")
    }
    func testCleanSolveStopsOnCardAndExposesSolutionsOnlyAfterResolution() async throws {
        let puzzle = testPuzzle([["a1a8"]])
        let model = SolveModel(puzzle, sleep: { _ in })
        XCTAssertTrue(model.lines.isEmpty); model.submit(try uci("a1a8")); XCTAssertEqual(model.phase, .replying)
        await waitUntil { model.done }
        XCTAssertEqual(model.phase, .solved); XCTAssertEqual(model.lines.count, 1); XCTAssertTrue(model.lines[0].played)
        XCTAssertEqual(model.runner.accepted.count, 1)
    }
    func testWrongMovesAreFreeOfBoardMutationButPermanentlyFailAttemptAndHint() async throws {
        let puzzle = testPuzzle([["a1a8"]])
        let model = SolveModel(puzzle, sleep: { _ in })
        model.submit(try uci("a1d4")); XCTAssertEqual(model.mistakes, 0)
        for _ in 0..<3 { model.submit(try uci("a1a2")) }
        XCTAssertEqual(model.fen, puzzle.fen); XCTAssertEqual(model.hint, try uci("a1a8")); XCTAssertTrue(model.lines.isEmpty)
        model.submit(try uci("a1a8")); await waitUntil { model.done }
        XCTAssertEqual(model.result, .failed); XCTAssertTrue(model.hinted); XCTAssertEqual(model.misses.first?.tried, ["Ra2", "Ra2", "Ra2"])
        XCTAssertEqual(model.misses.first?.wanted, "Ra8#")
    }
    func testFinalOpponentReplyLandsBeforeCardAndCancellationStopsIt() async throws {
        let puzzle = testPuzzle([["e2e4", "e7e5"]], fen: Board.defaultPosition)
        let model = SolveModel(puzzle, sleep: { _ in })
        model.submit(try uci("e2e4")); XCTAssertFalse(model.done)
        await waitUntil { model.done }
        XCTAssertEqual(Board.pieceAt(model.fen, "e5")?.type, .pawn)
        let cancelled = SolveModel(puzzle)
        cancelled.submit(try uci("e2e4")); cancelled.cancel()
        try await Task.sleep(for: .milliseconds(REPLY_MS + 200))
        XCTAssertNil(Board.pieceAt(cancelled.fen, "e5")); XCTAssertFalse(cancelled.done)
    }
    func testMissingPieceShowsAnswerAfterFailureAndCleanSolve() {
        let answer = Placement(color: .white, type: .knight, square: "g6")
        let puzzle = testPuzzle(fen: "7k/7p/5K2/8/8/8/8/8 b - - 0 1", addPiece: answer)
        let model = SolveModel(puzzle)
        model.submit(Placement(color: .white, type: .pawn, square: "g6")); XCTAssertEqual(model.fen, puzzle.fen)
        model.submit(answer); XCTAssertEqual(model.phase, .failed); XCTAssertEqual(Board.pieceAt(model.fen, "g6")?.type, .knight)
        let clean = SolveModel(puzzle); clean.submit(answer); XCTAssertEqual(clean.phase, .solved)
    }
    func testStartingReplacesScopeAndSkipRecordsAnAttemptWithoutSolveOrMiss() async throws {
        let storage = testStorage(), backend = MemoryBackend(testDataLibrary())
        let store = LibraryStore(account: TestAccount(User(id: "u", email: "e"), backend), cache: Cache(storage: storage), outbox: Outbox(storage: storage), defaults: UserDefaults(suiteName: newID())!)
        await store.open(); let app = AppState(store: store)
        await app.begin("c1", .ordered, ["p1"]); let first = try XCTUnwrap(store.library?.runs.first)
        try await Task.sleep(for: .milliseconds(2)); await app.begin("c1", .ordered, ["p1"])
        let run = try XCTUnwrap(store.library?.runs.first); XCTAssertNotEqual(first.id, run.id); XCTAssertEqual(store.library?.runs.count, 1)
        try await store.recordAttempt(Attempt(id: "skip", puzzleId: "p1", runId: run.id, result: .skipped, mistakes: 0, hinted: false, playedAt: 1))
        let progress = progressOf(try XCTUnwrap(store.library), run)
        XCTAssertNil(progress.current); XCTAssertEqual(progress.solved, 0); XCTAssertEqual(progress.failed, 0)
    }
}
