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
    /// Steps move on only through `proceed` unless `autoAdvance`, as most tests read each feedback.
    private func started(_ puzzle: ScanPuzzle, _ clock: TestClock, limits: ScanLimits = ScanLimits(),
                         autoAdvance: Bool = false) async -> ScanSolveModel {
        let model = ScanSolveModel(puzzle, limits: limits, clock: clock)
        model.autoAdvance = autoAdvance
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
        XCTAssertEqual(model.feedback?.verdict, .pass); XCTAssertEqual(model.feedback?.reason, "")
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 9))
        XCTAssertEqual(attempt.result, .solved); XCTAssertEqual(attempt.flagCall, false); XCTAssertEqual(attempt.runId, "r")
        XCTAssertEqual(attempt.detail.steps.quickScan?.ms, 4200); XCTAssertEqual(attempt.detail.steps.move?.ms, 1500)
        XCTAssertEqual(attempt.detail.steps.move?.played, kd8); XCTAssertEqual(attempt.detail.steps.move?.lossCp, 0)
        XCTAssertNil(attempt.detail.steps.quickScan?.limitMs)
    }

    func testNoFlagOnAFlaggedPositionFailsWhateverTheMove() async throws {
        let model = await started(puzzle(flagged: true), TestClock())
        model.call(false)
        XCTAssertEqual(model.feedback?.verdict, .fail); XCTAssertEqual(model.feedback?.title, "Missed the Tactic")
        model.proceed(); model.play(kd8)
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .failed); XCTAssertEqual(attempt.detail.failReason, .missedFlag)
        XCTAssertEqual(model.feedback?.title, "Good Move, Puzzle Failed"); XCTAssertNotNil(model.feedback?.note)
    }

    /// Playtest 3: No Flag says nothing changed, so it's off while a square is marked.
    func testNoFlagIsOffWhileASquareIsMarked() async {
        let model = await started(puzzle(flagged: true), TestClock())
        XCTAssertTrue(model.canCallNoFlag)
        model.toggle("d7"); XCTAssertFalse(model.canCallNoFlag)
        model.call(false); XCTAssertNil(model.feedback, "ignored with a mark on the board")
        model.toggle("d7"); XCTAssertTrue(model.canCallNoFlag)
        model.call(false); XCTAssertEqual(model.feedback?.title, "Missed the Tactic")
    }

    func testFlagOnAQuietPositionIsASoftMiss() async throws {
        let model = await started(puzzle(flagged: false, quickScan: []), TestClock())
        model.call(true)
        XCTAssertEqual(model.feedback?.verdict, .softMiss); XCTAssertEqual(model.feedback?.title, "It Was Quiet")
        model.proceed(); XCTAssertEqual(model.step, .move, "v1: the Tactic branch goes straight to the move")
        model.play(kf8)
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .solved); XCTAssertEqual(attempt.detail.softMisses, [.flaggedQuiet])
        XCTAssertEqual(model.feedback?.verdict, .softMiss)
        XCTAssertEqual(model.feedback?.reason, "−0.3. Best: Kd7.")
    }

    /// v9: a Tactic position can have tension already on the board and no piece to flag, so
    /// Tactic with nothing marked is a clean pass on the call (DosisLegalis 13).
    func testTacticWithAnEmptyQuickScanAndNoMarksPassesTheCall() async throws {
        let model = await started(puzzle(flagged: true, quickScan: []), TestClock())
        XCTAssertTrue(model.marks.isEmpty)
        model.call(true)
        XCTAssertEqual(model.feedback?.verdict, .pass); XCTAssertEqual(model.feedback?.title, "Clean Scan")
        XCTAssertEqual(ScanGrader.gradeFlag(called: true, answer: model.puzzle.answer), .pass)
        model.proceed(); model.play(kd8)
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .solved); XCTAssertEqual(attempt.flagCall, true)
        XCTAssertEqual(attempt.detail.steps.quickScan?.missed, []); XCTAssertEqual(attempt.detail.softMisses, [])
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
        XCTAssertEqual(model.feedback?.title, "Mistake"); XCTAssertEqual(model.feedback?.reason, "−3.0. Best: Kd7.")
        XCTAssertEqual(model.annotations.arrows, [BoardArrow(from: "e8", to: "d7", side: .own)])
    }

    func testMissedAndExtraSquaresAreRinged() async {
        let model = await started(puzzle(flagged: true, quickScan: ["d7", "c2"]), TestClock())
        model.toggle("a5"); model.toggle("d7"); model.call(true)
        XCTAssertEqual(model.annotations.rings, ["d7": .correct, "a5": .extra, "c2": .missed])
        XCTAssertEqual(model.annotations.tints, ["d7": .quickScan, "a5": .quickScan])
        XCTAssertEqual(model.feedback?.verdict, .softMiss); XCTAssertEqual(model.feedback?.title, "Missed a Piece")
        XCTAssertEqual(model.feedback?.misses, [ScanMissGroup(type: .quickScan(.attacked), items: ["c2"])])
        XCTAssertEqual(model.feedback?.spokenReason, "Attacked: c2")
    }

    func testOverTheTargetTimeIsASoftMiss() async throws {
        let clock = TestClock(), model = await started(puzzle(flagged: false, quickScan: []), clock)
        clock.advance(by: .seconds(12)); model.call(false)
        XCTAssertEqual(model.feedback?.title, "Right · slow"); XCTAssertEqual(model.feedback?.time, "12.0 / 10 s")
        model.proceed(); clock.advance(by: .seconds(6)); model.play(kd8)
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .solved); XCTAssertEqual(attempt.detail.softMisses, [.quickScanSlow, .moveSlow])
        XCTAssertEqual(model.feedback?.title, "Passed · slow: Quick Scan, Move", "only time was missed, each slow step named")
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

    /// The kings' position with a full scan: Black's king threatens d7, White's d2.
    private func fullScan() -> ScanPuzzle {
        ScanPuzzle(id: "f", content: testScanContent(flagged: true, quickScan: ["d1"], scores: ["e8f7": 300],
                                                     arrows: [ScanArrow(from: "e8", to: "d7", side: .own, kind: .threat),
                                                              ScanArrow(from: "d1", to: "d2", side: .theirs, kind: .threat)]),
                   addedAt: 0)
    }
    private func atArrows(_ clock: TestClock = TestClock(), limits: ScanLimits = ScanLimits()) async -> ScanSolveModel {
        let model = await started(fullScan(), clock, limits: limits)
        model.toggle("d1"); model.call(true); model.proceed()
        return model
    }

    /// v6: Flag runs the CCT arrows straight after the quick scan (no target step), then the move.
    func testFlagWithAFullScanRunsArrowsThenTheMove() async throws {
        let clock = TestClock(), model = await atArrows(clock)
        XCTAssertEqual(model.step, .arrows); XCTAssertEqual(model.step.title, "Checks, Captures, Threats")
        XCTAssertEqual(model.boardMode, .drawArrows)
        XCTAssertEqual(model.annotations.tints, ["d1": .quickScan], "the quick scan's mark stays")
        XCTAssertEqual(model.annotations.faded, ["d1"], "dimmed: it isn't the arrows' input"); XCTAssertNotNil(model.stepStarted)
        XCTAssertEqual(model.annotations.dots, [], "no fork or king-zone hints")
        model.drawArrow(from: "e8", to: "d7"); model.drawArrow(from: "d1", to: "c2")
        model.drawArrow(from: "a4", to: "a5")  // from an empty square: nothing
        model.drawArrow(from: "e8", to: "e6")  // no king move: refused
        XCTAssertEqual(model.current.arrows, [BoardArrow(from: "e8", to: "d7", side: .own), BoardArrow(from: "d1", to: "c2", side: .theirs)])
        clock.advance(by: .seconds(25)); model.finishStep()
        XCTAssertEqual(model.feedback?.title, "Missed an Arrow"); XCTAssertEqual(model.feedback?.time, "25.0 / 30 s")
        XCTAssertEqual(model.feedback?.misses, [ScanMissGroup(type: .arrow(.threat, .theirs), items: ["Kd2"])], "in SAN")
        XCTAssertEqual(model.annotations.arrows, [BoardArrow(from: "e8", to: "d7", side: .own, style: .correct),
                                                  BoardArrow(from: "d1", to: "c2", side: .theirs),
                                                  BoardArrow(from: "d1", to: "d2", side: .theirs, style: .missed)])

        model.proceed()
        XCTAssertEqual(model.step, .move); XCTAssertTrue(model.annotations.isEmpty)
        model.play(kd8); XCTAssertEqual(model.step, .finalCheck)
        model.confirm()
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .solved)
        XCTAssertNil(attempt.detail.steps.targets, "no target step is recorded")
        XCTAssertEqual(attempt.detail.steps.arrows, ScanMarkStep(ms: 25_000, limitMs: nil, missed: ["d1d2"], extra: ["d1c2"]))
        XCTAssertEqual(attempt.detail.softMisses, [.arrowsMissed])
    }

    /// v6: target marks are a thinking aid in the CCT step: a tap marks red / orange, a drag draws
    /// an arrow, with no tool to switch. Marks are never graded, stored or compared.
    func testTargetMarksAreAnUngradedAidInTheArrowsStep() async throws {
        let model = await atArrows()
        XCTAssertEqual(model.boardMode, .drawArrows); XCTAssertEqual(model.prompt, "", "no stage instructions (playtest 4)")
        model.tap("d1"); model.tap("d1")       // red first, then orange
        model.tap("e8")
        XCTAssertEqual(model.current.targets, ["d1": .orange, "e8": .red])
        XCTAssertEqual(model.annotations.tints, ["d1": .orange, "e8": .red])
        XCTAssertEqual(model.annotations.faded, [], "the step's own mark replaces the carried one")
        model.drawArrow(from: "e8", to: "d7"); model.drawArrow(from: "d1", to: "d2")
        XCTAssertEqual(model.current.lines, ["e8d7", "d1d2"], "drawn from marked pieces too")
        model.undo(); model.undo()
        XCTAssertEqual(model.current.arrows, [], "Undo goes back through the arrows")
        model.undo(); XCTAssertEqual(model.current.targets, ["d1": .orange], "and then the marks")
        model.drawArrow(from: "e8", to: "d7"); model.drawArrow(from: "d1", to: "d2")
        model.finishStep()
        XCTAssertEqual(model.feedback?.verdict, .pass); XCTAssertEqual(model.feedback?.title, "All Arrows Found")
        XCTAssertEqual(model.annotations.rings, [:], "marks get no rings: nothing compares them")
        XCTAssertEqual(model.annotations.tints, ["d1": .orange], "they stay as made")
        model.tap("a3"); XCTAssertNil(model.current.targets["a3"], "no marks once graded")
        model.proceed(); XCTAssertTrue(model.annotations.isEmpty, "not carried to the move")
        model.play(kd8); model.confirm()
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertNil(attempt.detail.steps.targets)
        XCTAssertEqual(attempt.detail.steps.arrows?.extra, [], "marks aren't arrows")
        XCTAssertEqual(attempt.detail.softMisses, [])
    }

    /// S08: after a full scan the move waits, ghosted, for Play It or Take Back; its time runs
    /// through the final check and take-backs are recorded.
    func testTheFinalCheckHoldsTheMoveGhosted() async throws {
        let clock = TestClock(), model = await atArrows(clock)
        model.finishStep(); model.proceed()
        XCTAssertEqual(model.step, .move); XCTAssertTrue(model.needsFinalCheck)
        let before = model.fen
        clock.advance(by: .seconds(2)); model.play(kf7)
        XCTAssertEqual(model.step, .finalCheck); XCTAssertEqual(model.step.title, "Final Check")
        XCTAssertEqual(model.candidate, kf7); XCTAssertEqual(model.candidateSan, "Kf7"); XCTAssertEqual(model.prompt, "Play Kf7")
        XCTAssertNil(model.outcome); XCTAssertNil(model.feedback); XCTAssertNotNil(model.stepStarted, "the clock keeps running")
        XCTAssertFalse(model.canMove); XCTAssertFalse(model.boardInteractive)
        XCTAssertEqual(model.fen, Board.applyUci(before, kf7)); XCTAssertEqual(model.highlight?.to, "f7")
        XCTAssertEqual(model.annotations.ghost, BoardGhost(square: "f7", piece: Board.Piece(square: "f7", type: .king, color: .black)))
        model.play(kd8); XCTAssertEqual(model.candidate, kf7, "no second move while one is held")

        clock.advance(by: .seconds(3)); model.takeBack()
        XCTAssertEqual(model.step, .move); XCTAssertEqual(model.fen, before); XCTAssertNil(model.candidate)
        XCTAssertNil(model.annotations.ghost); XCTAssertEqual(model.highlight?.to, "d1", "the last move is highlighted again")
        model.confirm(); XCTAssertEqual(model.step, .move, "nothing to play once taken back")

        clock.advance(by: .seconds(1)); model.play(kd8); model.confirm()
        XCTAssertEqual(model.step, .done); XCTAssertNil(model.annotations.ghost)
        XCTAssertEqual(model.attempt(runId: "r", playedAt: 1)?.result, .solved)
        let move = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1)?.detail.steps.move)
        XCTAssertEqual(move, ScanMoveStep(ms: 6000, limitMs: nil, played: kd8, lossCp: 0, takeBacks: 1))
        model.takeBack(); XCTAssertEqual(model.step, .done, "a graded move stays played")
    }

    func testNoFinalCheckWithoutAFullScan() async {
        let quiet = await started(puzzle(flagged: false, quickScan: []), TestClock())
        quiet.call(false); quiet.proceed(); quiet.play(kd8)
        XCTAssertEqual(quiet.step, .done, "Quiet plays at once"); XCTAssertNil(quiet.attempt(runId: "r", playedAt: 1)?.detail.steps.move?.takeBacks)
        let v1 = await started(puzzle(flagged: true), TestClock())
        v1.call(true); v1.proceed(); v1.play(kd8)
        XCTAssertEqual(v1.step, .done, "a v1 Tactic puzzle plays at once")
    }

    func testAQuietNoFlagOrNoFullScanGoesStraightToTheMove() async {
        let quiet = await started(puzzle(flagged: false, quickScan: []), TestClock())
        quiet.call(false); quiet.proceed(); XCTAssertEqual(quiet.step, .move, "a right Quiet skips the full scan")
        let v1 = await started(puzzle(flagged: true), TestClock())
        v1.call(true); v1.proceed(); XCTAssertEqual(v1.step, .move, "a puzzle without arrows skips it")
    }

    /// Playtest: a wrong No Flag used to skip the scan it most needed; now it runs it, the puzzle
    /// already failed, and the move is held and timed as after a Flag.
    func testAMissedFlagStillRunsTheFullScan() async throws {
        let clock = TestClock(), model = await started(fullScan(), clock)
        model.call(false)
        XCTAssertEqual(model.feedback?.title, "Missed the Tactic"); XCTAssertNil(model.outcome, "the puzzle goes on")
        XCTAssertTrue(model.runsFullScan)
        // Playtest 4: Skip from here records the fail already shown, not a skip.
        let settled = try XCTUnwrap(model.settledAttempt(runId: "r", playedAt: 1))
        XCTAssertEqual(settled.result, .failed); XCTAssertEqual(settled.detail.failReason, .missedFlag)
        XCTAssertEqual(settled.flagCall, false); XCTAssertTrue(settled.needsReview)
        model.proceed(); XCTAssertEqual(model.step, .arrows)
        XCTAssertNotNil(model.settledFail, "still failed through the arrows")
        model.drawArrow(from: "e8", to: "d7"); model.finishStep(); model.proceed()
        XCTAssertEqual(model.step, .move); XCTAssertTrue(model.needsFinalCheck)
        clock.advance(by: .seconds(7)); model.play(kd8); XCTAssertEqual(model.step, .finalCheck)
        model.confirm()
        XCTAssertNil(model.settledFail, "the result is the outcome now")
        XCTAssertEqual(model.feedback?.title, "Good Move, Puzzle Failed"); XCTAssertEqual(model.feedback?.note, "Missed the Tactic.")
        XCTAssertEqual(model.feedback?.time, "7.0 / 10 s", "timed as the flagged move")
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .failed); XCTAssertEqual(attempt.detail.failReason, .missedFlag)
        XCTAssertEqual(attempt.flagCall, false)
        XCTAssertNil(attempt.detail.steps.targets); XCTAssertEqual(attempt.detail.steps.arrows?.missed, ["d1d2"])
        XCTAssertFalse(attempt.detail.softMisses.contains(.moveSlow), "7 s is inside the flagged move's 10")
    }

    func testTheResultDrawsTheBestMoveOrTicksTheOnePlayed() async {
        let best = await started(puzzle(flagged: false, quickScan: []), TestClock())
        best.call(false); best.proceed(); best.play(kd8)
        XCTAssertEqual(best.annotations.arrows, [BoardArrow(from: "e8", to: "d8", side: .own, style: .correct)],
                       "a move scored best is confirmed on the board")
        let close = await started(puzzle(flagged: false, quickScan: []), TestClock())
        close.call(false); close.proceed(); close.play(kf8)
        XCTAssertEqual(close.feedback?.verdict, .pass)
        XCTAssertEqual(close.annotations.arrows, [BoardArrow(from: "e8", to: "d7", side: .own)], "passed, but not the best: the best is drawn")
        // The best line's reply, dashed (theirs), after the best move.
        var content = testScanContent(flagged: false, quickScan: [], scores: ["e8f7": 300])
        content.answer.bestLine = [Uci.parse("e8d7")!, Uci.parse("d1e2")!]
        let lined = await started(ScanPuzzle(id: "l", content: content, addedAt: 0), TestClock())
        lined.call(false); lined.proceed(); lined.play(kf7)
        XCTAssertEqual(lined.annotations.arrows, [BoardArrow(from: "e8", to: "d7", side: .own),
                                                  BoardArrow(from: "d1", to: "e2", side: .theirs)])
    }

    func testACleanStepMovesOnByItself() async {
        let clock = TestClock(), model = await started(puzzle(flagged: false, quickScan: []), clock, autoAdvance: true)
        model.call(false); XCTAssertEqual(model.feedback?.verdict, .pass)
        clock.advance(by: .milliseconds(ScanSolveModel.defaultAutoAdvanceMs - 100)); await settle { false }
        XCTAssertEqual(model.step, .quickScan, "the feedback shows first")
        clock.advance(by: .milliseconds(100)); await settle { model.step == .move }
        XCTAssertEqual(model.step, .move); XCTAssertNil(model.feedback)
        model.play(kd8)
        clock.advance(by: .seconds(5)); await settle { false }
        XCTAssertEqual(model.step, .done, "the result waits for Continue")

        let missed = await started(puzzle(flagged: true), clock, autoAdvance: true)
        missed.call(true); XCTAssertEqual(missed.feedback?.verdict, .softMiss)
        clock.advance(by: .seconds(5)); await settle { false }
        XCTAssertNotNil(missed.feedback, "a miss waits for Continue")

        let assisted = await started(puzzle(flagged: false, quickScan: []), clock, autoAdvance: true)
        assisted.autoAdvance = false; assisted.call(false)
        clock.advance(by: .seconds(5)); await settle { false }
        XCTAssertNotNil(assisted.feedback, "off with VoiceOver or Switch Control")
    }

    func testArrowUndoAndRedrawing() async {
        let manager = UndoManager(); manager.groupsByEvent = false
        let model = await atArrows()
        model.attach(manager)
        manager.beginUndoGrouping(); model.drawArrow(from: "e8", to: "d7"); manager.endUndoGrouping()
        manager.beginUndoGrouping(); model.drawArrow(from: "d1", to: "d2"); manager.endUndoGrouping()
        XCTAssertEqual(manager.undoActionName, "Arrow")
        manager.beginUndoGrouping(); model.removeArrow(at: 0); manager.endUndoGrouping()
        XCTAssertEqual(model.current.lines, ["d1d2"])
        model.undo(); XCTAssertEqual(model.current.arrows.map(\.line), ["e8d7", "d1d2"])
        model.undo(); XCTAssertEqual(model.current.lines, ["e8d7"])
        manager.redo(); XCTAssertEqual(model.current.lines, ["e8d7", "d1d2"])
        // Drawing an arrow that's there takes it away, undoably.
        manager.beginUndoGrouping(); model.drawArrow(from: "e8", to: "d7"); manager.endUndoGrouping()
        XCTAssertEqual(model.current.lines, ["d1d2"])
        model.undo(); XCTAssertEqual(model.current.lines, ["e8d7", "d1d2"])
        model.finishStep(); XCTAssertFalse(manager.canUndo, "the step's undo ends with it")
    }

    func testADragOfTargetsIsOneUndo() async {
        let manager = UndoManager(); manager.groupsByEvent = false
        let model = await atArrows()
        model.attach(manager)
        manager.beginUndoGrouping(); model.markTargets(["d7", "c7", "d1"]); manager.endUndoGrouping()
        XCTAssertEqual(manager.undoActionName, "Marks")
        model.undo(); XCTAssertEqual(model.current.targets, [:]); XCTAssertFalse(model.canUndo)
    }

    func testInputOutsideItsMarkingStepIsIgnored() async {
        let model = await atArrows()
        model.toggle("d7"); model.removeArrow(at: 0)
        XCTAssertEqual(model.current, ScanMarks(), "no quick-scan marks in the arrows step")
        let quick = await started(fullScan(), TestClock())
        quick.markTargets(["d7"]); quick.drawArrow(from: "e8", to: "d7")
        XCTAssertEqual(quick.current.targets, [:], "no target marks in the quick scan")
        XCTAssertEqual(quick.current.arrows, [], "nor arrows")
        let scanning = await started(fullScan(), TestClock())
        scanning.finishStep(); XCTAssertNil(scanning.feedback, "the quick scan ends with a call, not Next")
    }

    func testFeedbackWording() {
        let answer = testScanContent(flagged: true, scores: ["e8f7": 100_000]).answer
        let start = testScanContent().startFen!
        let outcome = ScanOutcome(result: .failed, detail: ScanAttemptDetail(failReason: .badMove))
        let lost = ScanFeedback.move(kf7, grade: ScanMoveGrade(passed: false, lossCp: 100_000), outcome: outcome,
                                     answer: answer, startFen: start, step: .flaggedMove, ms: 3000)
        XCTAssertEqual(lost.reason, "Throws away the mate. Best: Kd7.")
        XCTAssertEqual(lost.time, "3.0 / 10 s")
        let kept = ScanFeedback.move(kf8, grade: ScanMoveGrade(passed: true, lossCp: 400),
                                     outcome: ScanOutcome(result: .solved, detail: ScanAttemptDetail()),
                                     answer: answer, startFen: start, step: .quietMove, ms: 1000)
        XCTAssertEqual(kept.reason, "Keeps the mate."); XCTAssertEqual(kept.title, "Passed")
        // A piece on the missed square is named.
        let fen = "4k3/8/8/8/8/8/8/3QK3 w - - 0 1"
        let scan = ScanAnswer(flagged: true, quickScan: [ScanSquare(square: "d1", kind: .undefended)], moves: [:])
        let missed = ScanFeedback.quickScan(ScanMarkGrade(missed: ["d1"]), flag: .pass, answer: scan, startFen: fen, ms: 1000)
        XCTAssertEqual(missed.misses, [ScanMissGroup(type: .quickScan(.undefended), items: ["Qd1"])]); XCTAssertEqual(missed.reason, "")
        let unpinned = ScanAnswer(flagged: true, quickScan: [ScanSquare(square: "d1", kind: .unpinned)], moves: [:])
        XCTAssertEqual(ScanFeedback.quickScan(ScanMarkGrade(missed: ["d1"]), flag: .pass, answer: unpinned, startFen: fen, ms: 1000).misses,
                       [ScanMissGroup(type: .quickScan(.unpinned), items: ["Qd1"])])
        XCTAssertEqual(ScanSquare.Kind.unpinned.label, "Unpinned")
        XCTAssertEqual(ScanSquare.Kind.hanging.label, "Hanging")
        XCTAssertEqual(ScanMissCategory.quickScan(.hanging).title, "Hanging pieces")
    }

    /// Playtest 3: a slow quick scan, then a move in time, said "Passed, Slow" over the move's
    /// "2.8 / 5 s". The label names the slow step unless the move itself was slow.
    func testASlowLabelNamesTheSlowStep() {
        let answer = testScanContent().answer, start = testScanContent().startFen!
        func title(_ soft: [ScanSoftMiss]) -> String {
            ScanFeedback.move(kd8, grade: ScanMoveGrade(passed: true, lossCp: 0),
                              outcome: ScanOutcome(result: .solved, detail: ScanAttemptDetail(softMisses: soft)),
                              answer: answer, startFen: start, step: .quietMove, ms: 2800).title
        }
        XCTAssertEqual(title([.quickScanSlow]), "Passed · slow: Quick Scan")
        XCTAssertEqual(title([.arrowsSlow]), "Passed · slow: Arrows")
        XCTAssertEqual(title([.quickScanSlow, .arrowsSlow]), "Passed · slow: Quick Scan, Arrows")
        XCTAssertEqual(title([.moveSlow]), "Passed · slow: Move")
        XCTAssertEqual(title([.moveSlow, .quickScanSlow]), "Passed · slow: Quick Scan, Move", "in the order played")
        XCTAssertEqual(title([.arrowsMissed]), "Passed with Misses")
    }

    /// Playtest 3: "Last move: Re5", not "After Re5?", and "Play Nd6?", not "Nd6?": a bare "?"
    /// after a move reads as the annotation for a mistake.
    func testPromptsNeverPutAQuestionMarkStraightAfterAMove() async {
        let model = await started(fullScan(), TestClock())
        XCTAssertEqual(model.prompt, "Last move: \(model.lastMoveSan)")
    }

    /// One line per type in order of first appearance, every miss listed (no "+2"), arrows as SAN.
    func testMissesAreGroupedByType() {
        let fen = "4k3/8/8/8/8/8/8/3QK3 w - - 0 1"
        let arrows = ScanAnswer(flagged: true, quickScan: [], arrows: [
            ScanArrow(from: "d1", to: "d8", side: .own, kind: .check),
            ScanArrow(from: "e8", to: "f7", side: .theirs, kind: .threat),
            ScanArrow(from: "d1", to: "a4", side: .own, kind: .check)], moves: [:])
        let missed = ScanFeedback.arrows(ScanMarkGrade(missed: ["d1d8", "e8f7", "d1a4"]), answer: arrows, startFen: fen, ms: 1000)
        XCTAssertEqual(missed.misses, [ScanMissGroup(type: .arrow(.check, .own), items: ["Qd8+", "Qa4+"]),
                                       ScanMissGroup(type: .arrow(.threat, .theirs), items: ["Kf7"])])
        XCTAssertEqual(missed.spokenReason, "Your check: Qd8+, Qa4+. Their threat: Kf7")
        // Not a legal move (d8 is covered): still written as one.
        XCTAssertEqual(ScanFeedback.san(ScanArrow(from: "e8", to: "d8", side: .theirs, kind: .threat), fen), "Kd8")
        XCTAssertEqual(ScanFeedback.san(ScanArrow(from: "e8", to: "d1", side: .theirs, kind: .capture), fen), "Kxd1")
    }

    // MARK: Hard limits (S09)

    private let allLimits = ScanLimits(on: Set(ScanTimedStep.allCases))
    /// Lets the limit's task, woken by the clock, reach the main actor.
    private func settle(_ until: () -> Bool) async {
        for _ in 0..<100 where !until() { await Task.yield() }
    }

    func testAQuickScanThatRunsOutFailsTheFlaggedPuzzle() async throws {
        let clock = TestClock(), model = await started(puzzle(flagged: true), clock, limits: allLimits)
        XCTAssertNotNil(model.deadline)
        XCTAssertEqual(model.deadline?.timeIntervalSince(try XCTUnwrap(model.stepStarted)), 10)
        model.toggle("d7")
        clock.advance(by: .seconds(10)); await settle { model.feedback != nil }
        XCTAssertNil(model.flagCall); XCTAssertNil(model.deadline)
        XCTAssertEqual(model.feedback?.verdict, .fail); XCTAssertEqual(model.feedback?.title, "Time's Up")
        XCTAssertEqual(model.feedback?.reason, "Needed Tactic.")
        XCTAssertEqual(model.feedback?.time, "10.0 / 10 s limit")
        XCTAssertEqual(model.annotations.rings, ["d7": .correct], "the scan's rings stay on the board")
        model.proceed(); XCTAssertEqual(model.step, .quickScan, "the puzzle ends here: no move")
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .failed); XCTAssertEqual(attempt.detail.failReason, .noCall)
        XCTAssertNil(attempt.flagCall, "no call was made")
        XCTAssertEqual(attempt.detail.steps.quickScan, ScanMarkStep(ms: 10_000, limitMs: 10_000, missed: [], extra: [], timedOut: true))
        XCTAssertNil(attempt.detail.steps.move)
        XCTAssertEqual(attempt.detail.softMisses, [.quickScanSlow])
    }

    func testAQuickScanThatRunsOutFailsAQuietPuzzleToo() async throws {
        let clock = TestClock(), model = await started(puzzle(flagged: false, quickScan: []), clock, limits: allLimits)
        clock.advance(by: .seconds(10)); await settle { model.feedback != nil }
        XCTAssertEqual(model.feedback?.verdict, .fail); XCTAssertEqual(model.feedback?.reason, "Quiet.")
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .failed); XCTAssertEqual(attempt.detail.failReason, .noCall)
    }

    func testAStepFinishedInTimeCancelsItsLimit() async throws {
        let clock = TestClock(), model = await started(puzzle(flagged: false, quickScan: []), clock, limits: allLimits)
        clock.advance(by: .seconds(4)); model.call(false)
        XCTAssertEqual(model.feedback?.title, "Clean Scan"); XCTAssertEqual(model.feedback?.time, "4.0 / 10 s limit")
        clock.advance(by: .seconds(10)); await settle { false }
        XCTAssertEqual(model.step, .quickScan, "the cancelled limit does nothing"); XCTAssertEqual(model.flagCall, false)
        model.proceed()
        XCTAssertEqual(model.deadline?.timeIntervalSince(try XCTUnwrap(model.stepStarted)), 5, "the quiet move's 5 s")
        clock.advance(by: .seconds(2)); model.play(kd8)
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .solved); XCTAssertEqual(attempt.detail.softMisses, [])
        XCTAssertEqual(attempt.detail.steps.quickScan?.limitMs, 10_000); XCTAssertNil(attempt.detail.steps.quickScan?.timedOut)
        XCTAssertEqual(attempt.detail.steps.move?.limitMs, 5000)
    }

    func testNoMoveInTimeFails() async throws {
        let clock = TestClock(), model = await started(puzzle(flagged: false, quickScan: []), clock, limits: allLimits)
        model.call(false); model.proceed()
        clock.advance(by: .seconds(5)); await settle { model.outcome != nil }
        XCTAssertEqual(model.step, .done); XCTAssertFalse(model.boardInteractive)
        XCTAssertEqual(model.feedback?.verdict, .fail); XCTAssertEqual(model.feedback?.title, "Time's Up")
        XCTAssertEqual(model.feedback?.reason, "Best: Kd7.")
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .failed); XCTAssertEqual(attempt.detail.failReason, .noMove)
        XCTAssertNil(attempt.detail.steps.move?.played); XCTAssertEqual(attempt.detail.softMisses, [.moveSlow])
    }

    func testArrowsEndAsTheyStand() async throws {
        let clock = TestClock(), model = await atArrows(clock, limits: allLimits)
        XCTAssertEqual(model.deadline?.timeIntervalSince(try XCTUnwrap(model.stepStarted)), 30, "CCT gets 30 s")
        model.drawArrow(from: "e8", to: "d7"); model.drawArrow(from: "d1", to: "d2")
        clock.advance(by: .seconds(30)); await settle { model.feedback != nil }
        XCTAssertEqual(model.feedback?.title, "Time's Up"); XCTAssertEqual(model.feedback?.verdict, .softMiss, "all found, but out of time")
        model.proceed(); model.play(kd8); model.confirm()
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .solved)
        XCTAssertEqual(attempt.detail.steps.arrows, ScanMarkStep(ms: 30_000, limitMs: 30_000, missed: [], extra: [], timedOut: true))
        XCTAssertEqual(attempt.detail.softMisses, [.arrowsSlow])
    }

    func testTheMoveLimitRunsThroughTheFinalCheck() async throws {
        let clock = TestClock(), model = await atArrows(clock, limits: allLimits)
        model.finishStep(); model.proceed()
        let before = model.fen
        clock.advance(by: .seconds(4)); model.play(kd8); XCTAssertEqual(model.step, .finalCheck)
        clock.advance(by: .seconds(3)); model.takeBack(); model.play(kd8)
        clock.advance(by: .seconds(3)); await settle { model.outcome != nil }
        XCTAssertEqual(model.step, .done); XCTAssertNil(model.candidate); XCTAssertNil(model.annotations.ghost)
        XCTAssertEqual(model.fen, before, "a held move wasn't played")
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.detail.failReason, .noMove)
        XCTAssertEqual(attempt.detail.steps.move, ScanMoveStep(ms: 10_000, limitMs: 10_000, played: nil, lossCp: nil, takeBacks: 1))
    }

    func testLeavingCancelsTheLimit() async {
        let clock = TestClock(), model = await started(puzzle(flagged: true), clock, limits: allLimits)
        model.cancel()
        clock.advance(by: .seconds(10)); await settle { false }
        XCTAssertNil(model.feedback); XCTAssertNil(model.flagCall)
    }

    func testRecordOnlyStepsHaveNoDeadline() async {
        let model = await started(puzzle(flagged: true), TestClock(), limits: ScanLimits(on: [.arrows]))
        XCTAssertNil(model.deadline); XCTAssertNotNil(model.stepStarted)
    }

    // MARK: Playing the line out (v7)

    /// The flagged puzzle with two lines: Kd7 Ke1 Kd6 Kd1 Kd5, and Ke7 Kc1 Ke6. Kd8 (scored 0)
    /// is on neither; Kf8 (30) passes the table, Kf7 (300) fails it.
    private func linePuzzle() -> ScanPuzzle {
        var content = testScanContent(flagged: true, scores: ["e8f7": 300, "e8f8": 30])
        content.answer.solutions = [["e8d7", "d1e1", "d7d6", "e1d1", "d6d5"], ["e8e7", "d1c1", "e7e6"]].map { $0.map { Uci.parse($0)! } }
        content.version = 7
        return ScanPuzzle(id: "p", content: content, addedAt: 0)
    }
    private func atMove(_ clock: TestClock) async -> ScanSolveModel {
        let model = await started(linePuzzle(), clock)
        model.toggle("d7"); model.call(true); model.proceed()
        return model
    }
    private func reply(_ model: ScanSolveModel, _ clock: TestClock) async {
        while model.replying { clock.advance(by: .milliseconds(REPLY_MS)); await Task.yield() }
    }
    private func uci(_ text: String) -> Uci { Uci.parse(text)! }

    func testAFirstMoveOnTheLinePlaysItOutToTheEnd() async throws {
        let clock = TestClock(), model = await atMove(clock)
        model.play(uci("e8d7"))
        XCTAssertEqual(model.step, .line); XCTAssertTrue(model.replying); XCTAssertNil(model.outcome)
        XCTAssertFalse(model.canMove, "the board waits for their reply")
        XCTAssertEqual(model.prompt, "Their move.")
        await reply(model, clock)
        XCTAssertEqual(Board.pieceAt(model.fen, "e1")?.type, .king, "Ke1 was played")
        XCTAssertTrue(model.canMove); XCTAssertEqual(model.prompt, "Keep going.")
        model.play(uci("d7d6")); await reply(model, clock)
        clock.advance(by: .seconds(2))
        model.play(uci("d6d5"))
        XCTAssertEqual(model.step, .done)
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .solved)
        XCTAssertEqual(attempt.detail.steps.line?.played, [uci("d7d6"), uci("d6d5")])
        XCTAssertNil(attempt.detail.steps.line?.offLine)
        XCTAssertGreaterThanOrEqual(attempt.detail.steps.line?.ms ?? 0, 2000)
        XCTAssertEqual(model.feedback?.verdict, .pass); XCTAssertEqual(model.feedback?.reason, "")
        XCTAssertEqual(model.annotations.arrows, [])
    }

    func testTheSecondLineIsPlayedOutToo() async throws {
        let clock = TestClock(), model = await atMove(clock)
        model.play(uci("e8e7")); await reply(model, clock)
        XCTAssertEqual(Board.pieceAt(model.fen, "c1")?.type, .king, "the second line's reply, Kc1")
        model.play(uci("e7e6"))
        XCTAssertEqual(try XCTUnwrap(model.attempt(runId: "r", playedAt: 1)).result, .solved)
    }

    func testAMoveOffTheLineFailsAndShowsTheLine() async throws {
        let clock = TestClock(), model = await atMove(clock)
        model.play(uci("e8d7")); await reply(model, clock)
        let before = model.fen
        model.play(uci("d7c6"))
        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(model.fen, before, "the move off the line isn't played")
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .failed); XCTAssertEqual(attempt.detail.failReason, .offLine)
        XCTAssertEqual(attempt.detail.steps.line?.played, [uci("d7c6")])
        XCTAssertEqual(attempt.detail.steps.line?.offLine, true)
        XCTAssertGreaterThanOrEqual(attempt.detail.steps.line?.ms ?? 0, REPLY_MS, "timed from the first move")
        XCTAssertEqual(model.feedback?.verdict, .fail); XCTAssertEqual(model.feedback?.title, "Off the Line")
        XCTAssertEqual(model.feedback?.reason, "The line was 1... Kd7 2. Ke1 Kd6 3. Kd1 Kd5.")
        XCTAssertEqual(model.annotations.arrows, [BoardArrow(from: "d7", to: "d6", side: .own)])
    }

    func testAPassingFirstMoveOffTheLineEndsAsAPass() async throws {
        let model = await atMove(TestClock())
        model.play(uci("e8f8"))
        XCTAssertEqual(model.step, .done)
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .solved); XCTAssertNil(attempt.detail.steps.line)
        XCTAssertEqual(model.feedback?.reason, "Also works. The puzzle's line was 1... Kd7 2. Ke1 Kd6 3. Kd1 Kd5.")
    }

    func testAFailingFirstMoveOffTheLineFailsAsBefore() async throws {
        let model = await atMove(TestClock())
        model.play(kf7)
        let attempt = try XCTUnwrap(model.attempt(runId: "r", playedAt: 1))
        XCTAssertEqual(attempt.result, .failed); XCTAssertEqual(attempt.detail.failReason, .badMove)
        XCTAssertEqual(model.feedback?.title, "Mistake")
    }

    func testLeavingMidLineCancelsTheReply() async {
        let clock = TestClock(), model = await atMove(clock)
        model.play(uci("e8d7")); let fen = model.fen
        model.cancel(); clock.advance(by: .milliseconds(REPLY_MS)); await Task.yield()
        XCTAssertEqual(model.fen, fen); XCTAssertNil(model.outcome)
    }
}
