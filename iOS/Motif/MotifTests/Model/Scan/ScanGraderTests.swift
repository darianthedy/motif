import XCTest
@testable import Motif

final class ScanGraderTests: XCTestCase {
    private func answer(flagged: Bool = true, quickScan: [String] = ["e4", "c6"],
                        moves: [String: Int] = ["f3g5": 0, "d2d3": 50, "b1c3": 51, "c4f7": 310],
                        arrows: [ScanArrow]? = nil) -> ScanAnswer {
        ScanAnswer(flagged: flagged, quickScan: quickScan.map { ScanSquare(square: $0, kind: .attacked) },
                   arrows: arrows, moves: moves, bestLine: nil)
    }
    private func move(_ text: String) -> Uci { Uci.parse(text)! }

    func testQuickScanListsMissedInAnswerOrderAndExtrasSorted() {
        let grade = ScanGrader.gradeQuickScan(tapped: ["h1", "c6", "a1"], answer: answer(quickScan: ["e4", "c6", "b2"]))
        XCTAssertEqual(grade, ScanMarkGrade(missed: ["e4", "b2"], extra: ["a1", "h1"]))
        XCTAssertEqual(ScanGrader.gradeQuickScan(tapped: [], answer: answer(quickScan: [])), ScanMarkGrade())
    }

    func testFlagCall() {
        XCTAssertEqual(ScanGrader.gradeFlag(called: true, answer: answer(flagged: true)), .pass)
        XCTAssertEqual(ScanGrader.gradeFlag(called: false, answer: answer(flagged: false)), .pass)
        XCTAssertEqual(ScanGrader.gradeFlag(called: false, answer: answer(flagged: true)), .fail)
        XCTAssertEqual(ScanGrader.gradeFlag(called: true, answer: answer(flagged: false)), .softMiss)
    }

    func testArrowsCompareFromAndToAndSkipWithoutAnswer() {
        let arrows = [ScanArrow(from: "f3", to: "g5", side: .own, kind: .threat),
                      ScanArrow(from: "f6", to: "e4", side: .theirs, kind: .capture)]
        XCTAssertEqual(ScanGrader.gradeArrows(drawn: ["f3g5", "a1a8"], answer: answer(arrows: arrows)),
                       ScanMarkGrade(missed: ["f6e4"], extra: ["a1a8"]))
        XCTAssertNil(ScanGrader.gradeArrows(drawn: ["f3g5"], answer: answer()))
    }

    /// v4: an optional arrow counts when drawn and isn't missed when left out; required arrows
    /// still must be drawn, and an arrow not in the list is still extra.
    func testOptionalArrowsAreNeverMissed() {
        let arrows = [ScanArrow(from: "f3", to: "g5", side: .own, kind: .threat, optional: true),
                      ScanArrow(from: "f6", to: "e4", side: .theirs, kind: .capture)]
        let a = answer(arrows: arrows)
        XCTAssertEqual(ScanGrader.gradeArrows(drawn: ["f6e4"], answer: a), ScanMarkGrade())
        XCTAssertEqual(ScanGrader.gradeArrows(drawn: ["f6e4", "f3g5"], answer: a), ScanMarkGrade())
        XCTAssertEqual(ScanGrader.gradeArrows(drawn: ["f3g5", "a1a8"], answer: a),
                       ScanMarkGrade(missed: ["f6e4"], extra: ["a1a8"]))
    }

    func testOptionalRoundTripsAndDefaultsToRequired() throws {
        let optional = ScanArrow(from: "f3", to: "g5", side: .own, kind: .threat, optional: true)
        let required = ScanArrow(from: "f6", to: "e4", side: .theirs, kind: .capture)
        let data = try JSONEncoder().encode([optional, required])
        XCTAssertEqual(try JSONDecoder().decode([ScanArrow].self, from: data), [optional, required])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(required), as: UTF8.self).contains("optional"))
    }

    func testMovePassesWithinHalfAPawn() {
        let a = answer()
        XCTAssertEqual(ScanGrader.gradeMove(move("f3g5"), answer: a), ScanMoveGrade(passed: true, lossCp: 0))
        XCTAssertEqual(ScanGrader.gradeMove(move("d2d3"), answer: a), ScanMoveGrade(passed: true, lossCp: 50))
        XCTAssertEqual(ScanGrader.gradeMove(move("b1c3"), answer: a), ScanMoveGrade(passed: false, lossCp: 51))
        XCTAssertEqual(ScanGrader.gradeMove(move("b1c3"), answer: a, margin: 60).passed, true)
        XCTAssertEqual(ScanGrader.gradeMove(move("a2a3"), answer: a), ScanMoveGrade(passed: false, lossCp: nil))
    }

    func testAMoveThatKeepsAForcedMatePasses() {
        let a = answer(moves: ["d8h4": 0, "d8f6": 900, "a7a6": ScanAnswer.lostMateCp])
        XCTAssertTrue(ScanGrader.gradeMove(move("d8f6"), answer: a).passed)
        XCTAssertFalse(ScanGrader.gradeMove(move("a7a6"), answer: a).passed)
        // No mate on the board: a big loss is a big loss.
        XCTAssertFalse(ScanGrader.gradeMove(move("c4f7"), answer: answer()).passed)
    }

    private func steps(quickMs: Int = 4000, missed: [String] = [], played: String? = "f3g5", moveMs: Int = 3000) -> ScanSteps {
        ScanSteps(quickScan: ScanMarkStep(ms: quickMs, limitMs: nil, missed: missed, extra: []),
                  move: ScanMoveStep(ms: moveMs, limitMs: nil, played: played.map(move), lossCp: nil))
    }

    func testResultPassesACleanScan() {
        let outcome = ScanGrader.result(of: steps(), flagCall: true, answer: answer())
        XCTAssertEqual(outcome.result, .solved)
        XCTAssertEqual(outcome.detail.softMisses, []); XCTAssertNil(outcome.detail.failReason)
    }

    func testResultFailsAMissedFlagBeforeABadMove() {
        let outcome = ScanGrader.result(of: steps(played: "c4f7"), flagCall: false, answer: answer())
        XCTAssertEqual(outcome.result, .failed); XCTAssertEqual(outcome.detail.failReason, .missedFlag)
    }

    func testResultFailsABadMoveOrNoMove() {
        XCTAssertEqual(ScanGrader.result(of: steps(played: "c4f7"), flagCall: true, answer: answer()).detail.failReason, .badMove)
        XCTAssertEqual(ScanGrader.result(of: steps(played: nil), flagCall: true, answer: answer()).detail.failReason, .noMove)
        XCTAssertEqual(ScanGrader.result(of: ScanSteps(), flagCall: true, answer: answer()).detail.failReason, .noMove)
    }

    func testSoftMissesNeverFail() {
        let outcome = ScanGrader.result(of: steps(quickMs: 10_001, missed: ["c6"]), flagCall: true, answer: answer(flagged: false))
        XCTAssertEqual(outcome.result, .solved)
        XCTAssertEqual(outcome.detail.softMisses, [.flaggedQuiet, .quickScanMissed, .quickScanSlow])
    }

    func testFullScanSoftMisses() {
        var s = steps()
        s.arrows = ScanMarkStep(ms: 30_001, missed: ["f3g5"])
        XCTAssertEqual(ScanGrader.result(of: s, flagCall: true, answer: answer()).detail.softMisses,
                       [.arrowsMissed, .arrowsSlow])
        s.arrows = ScanMarkStep(ms: 30_000)
        XCTAssertEqual(ScanGrader.result(of: s, flagCall: true, answer: answer()).detail.softMisses, [], "30 s is in time")
    }

    /// v6: there is no target step, so nothing about targets is ever given, even for a step an
    /// older attempt recorded (`steps.targets`).
    func testNoTargetMissesOrTimes() {
        var s = steps()
        s.targets = ScanMarkStep(ms: 25_000, missed: ["f7"]); s.arrows = ScanMarkStep(ms: 1000)
        let outcome = ScanGrader.result(of: s, flagCall: true, answer: answer())
        XCTAssertEqual(outcome.detail.softMisses, [])
        XCTAssertEqual(outcome.result, .solved)
    }

    func testTheMoveTargetFollowsTheCall() {
        XCTAssertEqual(ScanGrader.result(of: steps(moveMs: 6000), flagCall: false, answer: answer(flagged: false)).detail.softMisses, [.moveSlow])
        XCTAssertEqual(ScanGrader.result(of: steps(moveMs: 6000), flagCall: true, answer: answer()).detail.softMisses, [])
        XCTAssertEqual(ScanGrader.result(of: steps(moveMs: 10_001), flagCall: true, answer: answer()).detail.softMisses, [.moveSlow])
    }

    func testTargetTimes() {
        XCTAssertEqual(ScanTimedStep.allCases.map(ScanTiming.targetMs), [10_000, 5_000, 30_000, 10_000])
        XCTAssertEqual(ScanTimedStep.allCases.compactMap(ScanLimits().limitMs), [], "no limits by default")
        XCTAssertFalse(ScanTiming.isOverTarget(10_000, .quickScan)); XCTAssertTrue(ScanTiming.isOverTarget(10_001, .quickScan))
    }

    /// S09: a step the limit cut off is over its target, even at exactly the limit.
    func testATimedOutStepIsSlow() {
        var s = steps(quickMs: 10_000, played: nil, moveMs: 10_000)
        s.arrows = ScanMarkStep(ms: 30_000, limitMs: 30_000, timedOut: true)
        let outcome = ScanGrader.result(of: s, flagCall: true, answer: answer())
        XCTAssertEqual(outcome.detail.softMisses, [.arrowsSlow, .moveSlow])
        XCTAssertEqual(outcome.detail.failReason, .noMove)
    }

    /// S09: a quick scan that ran out had no call: it fails on a flagged and a quiet position alike.
    func testAQuickScanThatRanOutFailsEveryPosition() {
        var s = ScanSteps(quickScan: ScanMarkStep(ms: 10_000, limitMs: 10_000, timedOut: true))
        for flagged in [true, false] {
            let outcome = ScanGrader.result(of: s, flagCall: false, answer: answer(flagged: flagged))
            XCTAssertEqual(outcome.result, .failed); XCTAssertEqual(outcome.detail.failReason, .noCall)
            XCTAssertEqual(outcome.detail.softMisses, [.quickScanSlow])
        }
        s.quickScan?.missed = ["c6"]
        XCTAssertEqual(ScanGrader.result(of: s, flagCall: false, answer: answer()).detail.softMisses, [.quickScanMissed, .quickScanSlow])
    }

    func testAttemptFromAnOutcomeAndASkip() {
        let outcome = ScanGrader.result(of: steps(played: "c4f7"), flagCall: true, answer: answer())
        let attempt = ScanAttempt(id: "a", puzzleId: "p", runId: "r", flagCall: true, outcome: outcome, playedAt: 9)
        XCTAssertEqual(attempt.result, .failed); XCTAssertEqual(attempt.mistakes, 1); XCTAssertEqual(attempt.flagCall, true)
        let skip = ScanAttempt.skip(id: "s", puzzleId: "p", runId: "r", playedAt: 9)
        XCTAssertEqual(skip.result, .skipped); XCTAssertNil(skip.flagCall); XCTAssertEqual(skip.mistakes, 0)
    }

    // MARK: Format v7: lines and win chance

    func testWinPctMatchesEngineDotPy() {
        // engine.py win_pct: 50 at 0, symmetric, ~95 at +8.
        XCTAssertEqual(ScanGrader.winPct(0), 50, accuracy: 1e-9)
        XCTAssertEqual(ScanGrader.winPct(800), 95.01, accuracy: 0.01)
        XCTAssertEqual(ScanGrader.winPct(-300) + ScanGrader.winPct(300), 100, accuracy: 1e-9)
    }

    /// Book #241: Qb4 is 0.66 behind Qa4 at +8. Under 10 points of win chance lost passes when the
    /// best is clearly winning; the flat 50 cp still decides below +3 or without `bestCp`.
    func testAClearlyWinningPositionIsGradedByWinChanceLost() {
        var a = answer(moves: ["f3g5": 0, "d2d3": 66, "b1c3": 400, "c4f7": 310])
        XCTAssertFalse(ScanGrader.gradeMove(move("d2d3"), answer: a).passed, "no bestCp: 50 cp")
        a.bestCp = 800
        XCTAssertEqual(ScanGrader.winPctLost(lossCp: 66, answer: a) ?? 99, 1.3, accuracy: 0.05)
        XCTAssertTrue(ScanGrader.gradeMove(move("d2d3"), answer: a).passed)
        XCTAssertFalse(ScanGrader.gradeMove(move("b1c3"), answer: a).passed, "+8 to +4 loses 13.7 points")
        a.bestCp = 299
        XCTAssertFalse(ScanGrader.gradeMove(move("d2d3"), answer: a).passed, "not clearly winning: 50 cp")
    }

    func testAForcedMateStillPassesWithBestCp() {
        var a = answer(moves: ["f3g5": 0, "d2d3": 4, "b1c3": 100_000, "c4f7": 100_000])
        a.bestCp = ScanAnswer.lostMateCp
        XCTAssertTrue(ScanGrader.gradeMove(move("d2d3"), answer: a).passed)
        XCTAssertFalse(ScanGrader.gradeMove(move("b1c3"), answer: a).passed)
    }

    func testAMoveStartingAnyLineAlwaysPasses() {
        var a = answer()
        a.solutions = [[move("f3g5"), move("d7d5")], [move("c4f7"), move("e8f7")]]
        XCTAssertEqual(ScanGrader.gradeMove(move("c4f7"), answer: a), ScanMoveGrade(passed: true, lossCp: 310, onLine: true))
        XCTAssertEqual(ScanGrader.gradeMove(move("d2d3"), answer: a), ScanMoveGrade(passed: true, lossCp: 50))
        XCTAssertFalse(ScanGrader.gradeMove(move("b1c3"), answer: a).passed)
    }

    func testLaterMovesMatchExactlyTheLinesThatStillFit() {
        let lines = [[move("f3g5"), move("d7d5"), move("e4d5")], [move("f3g5"), move("d7d5"), move("c4d5")],
                     [move("c4f7"), move("e8f7"), move("f3g5")]]
        let root = buildTrie(lines)
        let after = try! XCTUnwrap(ScanGrader.gradeLineMove(move("f3g5"), at: root))
        XCTAssertEqual(after.reply, move("d7d5"))
        XCTAssertNotNil(ScanGrader.gradeLineMove(move("e4d5"), at: after.next))
        XCTAssertNotNil(ScanGrader.gradeLineMove(move("c4d5"), at: after.next))
        XCTAssertNil(ScanGrader.gradeLineMove(move("f3g5"), at: after.next), "the other line's move doesn't fit")
        var a = answer(); a.solutions = lines
        XCTAssertEqual(ScanGrader.shownLine(a, fitting: [move("c4f7"), move("e8f7")]), lines[2])
        XCTAssertEqual(ScanGrader.shownLine(a, fitting: []), lines[0])
    }

    func testOffTheLineFailsAfterAPassingFirstMove() {
        var a = answer(); a.solutions = [[move("f3g5"), move("d7d5"), move("e4d5")]]
        var steps = ScanSteps(quickScan: ScanMarkStep(ms: 1000), move: ScanMoveStep(ms: 1000, played: move("f3g5"), lossCp: 0))
        steps.line = ScanLineStep(ms: 900, played: [move("c4d5")], offLine: true)
        let outcome = ScanGrader.result(of: steps, flagCall: true, answer: a)
        XCTAssertEqual(outcome.result, .failed); XCTAssertEqual(outcome.detail.failReason, .offLine)
        steps.line = ScanLineStep(ms: 900, played: [move("e4d5")])
        XCTAssertEqual(ScanGrader.result(of: steps, flagCall: true, answer: a).result, .solved)
    }
}
