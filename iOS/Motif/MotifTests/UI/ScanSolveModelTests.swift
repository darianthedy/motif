import XCTest
@testable import Motif

/// Scan plan §10, `ScanSolveModel`: each branch of the v1 step order, timing from an injected
/// clock, undo through `UndoManager`, and the attempt it builds. No waiting: the clock is stepped.
@MainActor final class ScanSolveModelTests: XCTestCase {
    /// Black to move after 1. Kd1; Kd7, Kd8 and Ke7 are best (Kd7 shown first), Kf7 gives away 3 pawns.
    private func puzzle(flagged: Bool, quickScan: [String] = ["d7"]) -> ScanPuzzle {
        ScanPuzzle(id: "p", content: testScanContent(flagged: flagged, quickScan: quickScan,
                                                     scores: ["e8f7": 300, "e8f8": 30]), addedAt: 0)
    }
    private func started(_ puzzle: ScanPuzzle, _ clock: TestClock) async -> ScanSolveModel {
        let model = ScanSolveModel(puzzle, clock: clock)
        let task = Task { await model.begin() }
        while model.step == .lastMove { clock.advance(by: .milliseconds(REPLY_MS)); await Task.yield() }
        await task.value
        return model
    }
    private let kd8 = Uci.parse("e8d8")!, kf7 = Uci.parse("e8f7")!, kf8 = Uci.parse("e8f8")!

    func testLastMovePlaysThenTheQuickScanStarts() async {
        let clock = TestClock(), model = ScanSolveModel(puzzle(flagged: false), clock: clock)
        XCTAssertEqual(model.step, .lastMove); XCTAssertEqual(model.fen, scanTestFen); XCTAssertFalse(model.boardInteractive)
        let task = Task { await model.begin() }
        while model.step == .lastMove { clock.advance(by: .milliseconds(REPLY_MS)); await Task.yield() }
        await task.value
        XCTAssertEqual(model.step, .quickScan); XCTAssertEqual(model.boardMode, .markSquares)
        XCTAssertEqual(model.fen, model.puzzle.startFen); XCTAssertEqual(model.solver, .black)
        XCTAssertEqual(model.highlight?.from, "e1"); XCTAssertEqual(model.highlight?.to, "d1")
        XCTAssertNotNil(model.stepStarted)
    }

    func testCancelledBeforeTheLastMoveStaysAtTheStart() async {
        let clock = TestClock(), model = ScanSolveModel(puzzle(flagged: false), clock: clock)
        let task = Task { await model.begin() }
        task.cancel(); await Task.yield(); clock.advance(by: .milliseconds(REPLY_MS)); await task.value
        // TestClock's sleep doesn't throw on cancel; the model checks for it.
        XCTAssertEqual(model.step, .lastMove)
    }

    func testQuietPuzzleNoFlagAndTheBestMovePasses() async throws {
        let clock = TestClock(), model = await started(puzzle(flagged: false, quickScan: []), clock)
        clock.advance(by: .milliseconds(4200))
        model.call(false)
        XCTAssertEqual(model.feedback?.verdict, .pass); XCTAssertEqual(model.feedback?.title, "Clean Scan")
        XCTAssertNil(model.stepStarted); XCTAssertFalse(model.canMark)
        model.proceed()
        XCTAssertEqual(model.step, .move); XCTAssertEqual(model.boardMode, .play); XCTAssertTrue(model.boardInteractive)
        clock.advance(by: .milliseconds(1500))
        model.play(kd8)
        XCTAssertEqual(model.step, .done); XCTAssertFalse(model.boardInteractive)
        XCTAssertEqual(model.feedback?.verdict, .pass); XCTAssertEqual(model.feedback?.reason, "Kd8 is the best move.")
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 9))
        XCTAssertEqual(attempt.result, .solved); XCTAssertEqual(attempt.flagCall, false); XCTAssertEqual(attempt.runId, "r")
        XCTAssertEqual(attempt.detail.steps.quickScan?.ms, 4200); XCTAssertEqual(attempt.detail.steps.move?.ms, 1500)
        XCTAssertEqual(attempt.detail.steps.move?.played, kd8); XCTAssertEqual(attempt.detail.steps.move?.lossCp, 0)
        XCTAssertNil(attempt.detail.steps.quickScan?.limitMs)
    }

    func testNoFlagOnAFlaggedPositionFailsWhateverTheMove() async throws {
        let model = await started(puzzle(flagged: true), TestClock())
        model.toggle("d7"); model.call(false)
        XCTAssertEqual(model.feedback?.verdict, .fail); XCTAssertEqual(model.feedback?.title, "Missed the Flag")
        model.proceed(); model.play(kd8)
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .failed); XCTAssertEqual(attempt.detail.failReason, .missedFlag)
        XCTAssertEqual(model.feedback?.title, "Good Move, Puzzle Failed"); XCTAssertNotNil(model.feedback?.note)
    }

    func testFlagOnAQuietPositionIsASoftMiss() async throws {
        let model = await started(puzzle(flagged: false, quickScan: []), TestClock())
        model.call(true)
        XCTAssertEqual(model.feedback?.verdict, .softMiss); XCTAssertEqual(model.feedback?.title, "No Flag Needed")
        model.proceed(); XCTAssertEqual(model.step, .move, "v1: the Flag branch goes straight to the move")
        model.play(kf8)
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .solved); XCTAssertEqual(attempt.detail.softMisses, [.flaggedQuiet])
        XCTAssertEqual(model.feedback?.verdict, .softMiss)
        XCTAssertEqual(model.feedback?.reason, "Kf8 is within half a pawn of Kd7 (−0.3).")
    }

    func testABadMoveFailsAndShowsTheBestMove() async throws {
        let model = await started(puzzle(flagged: true), TestClock())
        model.toggle("d7"); model.call(true)
        XCTAssertEqual(model.feedback?.verdict, .pass)
        XCTAssertEqual(model.annotations.rings, ["d7": .correct])
        model.proceed(); XCTAssertTrue(model.annotations.isEmpty, "the move starts on a clean board")
        model.play(kf7)
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .failed); XCTAssertEqual(attempt.detail.failReason, .badMove)
        XCTAssertEqual(model.feedback?.title, "Mistake"); XCTAssertEqual(model.feedback?.reason, "Kf7 loses 3.0. Best was Kd7.")
        XCTAssertEqual(model.annotations.arrows, [BoardArrow(from: "e8", to: "d7", side: .own)])
    }

    func testMissedAndExtraSquaresAreRinged() async {
        let model = await started(puzzle(flagged: true, quickScan: ["d7", "c2"]), TestClock())
        model.toggle("a5"); model.toggle("d7"); model.call(true)
        XCTAssertEqual(model.annotations.rings, ["d7": .correct, "a5": .extra, "c2": .missed])
        XCTAssertEqual(model.annotations.tints, ["d7": .quickScan, "a5": .quickScan])
        XCTAssertEqual(model.feedback?.verdict, .softMiss); XCTAssertEqual(model.feedback?.title, "Missed a Square")
        XCTAssertEqual(model.feedback?.reason, "Missed c2, now attacked.")
    }

    func testOverTheTargetTimeIsASoftMiss() async throws {
        let clock = TestClock(), model = await started(puzzle(flagged: false, quickScan: []), clock)
        clock.advance(by: .seconds(12)); model.call(false)
        XCTAssertEqual(model.feedback?.title, "Right, but Slow"); XCTAssertEqual(model.feedback?.time, "12.0 s · target 10 s")
        model.proceed(); clock.advance(by: .seconds(6)); model.play(kd8)
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .solved); XCTAssertEqual(attempt.detail.softMisses, [.quickScanSlow, .moveSlow])
    }

    func testUndoGoesThroughTheUndoManagerAndNeverLeavesTheStep() async {
        let manager = UndoManager(); manager.groupsByEvent = false
        let model = await started(puzzle(flagged: true), TestClock())
        model.attach(manager)
        XCTAssertFalse(model.canUndo)
        manager.beginUndoGrouping(); model.toggle("d7"); manager.endUndoGrouping()
        manager.beginUndoGrouping(); model.toggle("a5"); manager.endUndoGrouping()
        XCTAssertEqual(model.marks, ["d7", "a5"]); XCTAssertEqual(manager.undoActionName, "Mark")
        model.undo()   // the Undo button
        XCTAssertEqual(model.marks, ["d7"])
        manager.undo()  // shake to undo
        XCTAssertEqual(model.marks, []); XCTAssertFalse(model.canUndo)
        manager.redo(); XCTAssertEqual(model.marks, ["d7"]); XCTAssertTrue(model.canUndo)
        model.call(true)
        XCTAssertFalse(model.canUndo); XCTAssertFalse(manager.canUndo, "the step's undo ends with it")
        model.undo(); XCTAssertEqual(model.marks, ["d7"])
    }

    func testUndoWithoutAnUndoManager() async {
        let model = await started(puzzle(flagged: true), TestClock())
        model.toggle("d7"); model.toggle("d7"); model.toggle("a5")
        model.undo(); XCTAssertEqual(model.marks, [])
        model.undo(); XCTAssertEqual(model.marks, ["d7"])
    }

    func testInputOutsideItsStepIsIgnored() async {
        let model = await started(puzzle(flagged: false), TestClock())
        model.play(kd8); XCTAssertEqual(model.step, .quickScan, "no move during the quick scan")
        model.proceed(); XCTAssertEqual(model.step, .quickScan, "no Continue before the call")
        model.call(false); model.toggle("a5"); XCTAssertEqual(model.marks, [])
        model.call(true); XCTAssertEqual(model.flagCall, false, "one call per puzzle")
        model.proceed(); model.play(Uci.parse("e8e6")!); XCTAssertEqual(model.step, .move, "illegal moves are ignored")
    }

    func testFeedbackWording() {
        let answer = testScanContent(flagged: true, scores: ["e8f7": 100_000]).answer
        let start = testScanContent().startFen!
        let outcome = ScanOutcome(result: .failed, detail: ScanAttemptDetail(failReason: .badMove))
        let lost = ScanFeedback.move(kf7, grade: ScanMoveGrade(passed: false, lossCp: 100_000), outcome: outcome,
                                     answer: answer, startFen: start, flagCall: true, ms: 3000)
        XCTAssertEqual(lost.reason, "Kf7 throws away a forced mate. Best was Kd7.")
        XCTAssertEqual(lost.time, "3.0 s · target 10 s")
        let kept = ScanFeedback.move(kf8, grade: ScanMoveGrade(passed: true, lossCp: 400),
                                     outcome: ScanOutcome(result: .solved, detail: ScanAttemptDetail()),
                                     answer: answer, startFen: start, flagCall: false, ms: 1000)
        XCTAssertEqual(kept.reason, "Kf8 keeps the forced mate."); XCTAssertEqual(kept.title, "Passed")
        // A piece on the missed square is named.
        let fen = "4k3/8/8/8/8/8/8/3QK3 w - - 0 1"
        let scan = ScanAnswer(flagged: true, quickScan: [ScanSquare(square: "d1", kind: .undefended)], moves: [:])
        let missed = ScanFeedback.quickScan(ScanMarkGrade(missed: ["d1"]), flag: .pass, answer: scan, startFen: fen, ms: 1000)
        XCTAssertEqual(missed.reason, "Missed the queen on d1, no longer defended.")
    }
}
