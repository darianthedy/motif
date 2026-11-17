import XCTest
@testable import Motif

final class ScanGraderTests: XCTestCase {
    private func answer(flagged: Bool = true, quickScan: [String] = ["e4", "c6"],
                        moves: [String: Int] = ["f3g5": 0, "d2d3": 50, "b1c3": 51, "c4f7": 310],
                        targets: ScanTargets? = nil, arrows: [ScanArrow]? = nil) -> ScanAnswer {
        ScanAnswer(flagged: flagged, quickScan: quickScan.map { ScanSquare(square: $0, kind: .attacked) },
                   targets: targets, arrows: arrows, moves: moves, bestLine: nil)
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

    func testTargetsNeedTheRightColourAndDotsCoverKingZoneAndFork() {
        let targets = ScanTargets(red: ["f7"], orange: ["e5"], kingZone: ["g7"], fork: ["d5"])
        let a = answer(targets: targets)
        XCTAssertEqual(ScanGrader.gradeTargets(red: ["f7"], orange: ["e5"], dots: ["g7", "d5"], answer: a), ScanMarkGrade())
        // Wrong colour is a miss, not an extra; a stray dot is an extra.
        XCTAssertEqual(ScanGrader.gradeTargets(red: ["e5"], orange: ["f7"], dots: ["g7", "a3"], answer: a),
                       ScanMarkGrade(missed: ["f7", "e5", "d5"], extra: ["a3"]))
        XCTAssertNil(ScanGrader.gradeTargets(red: [], orange: [], dots: [], answer: answer()))
    }

    func testArrowsCompareFromAndToAndSkipWithoutAnswer() {
        let arrows = [ScanArrow(from: "f3", to: "g5", side: .own, kind: .threat),
                      ScanArrow(from: "f6", to: "e4", side: .theirs, kind: .capture)]
        XCTAssertEqual(ScanGrader.gradeArrows(drawn: ["f3g5", "a1a8"], answer: answer(arrows: arrows)),
                       ScanMarkGrade(missed: ["f6e4"], extra: ["a1a8"]))
        XCTAssertNil(ScanGrader.gradeArrows(drawn: ["f3g5"], answer: answer()))
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
        s.targets = ScanMarkStep(ms: 20_001, missed: ["f7"]); s.arrows = ScanMarkStep(ms: 1000, missed: ["f3g5"])
        XCTAssertEqual(ScanGrader.result(of: s, flagCall: true, answer: answer()).detail.softMisses,
                       [.targetsMissed, .targetsSlow, .arrowsMissed])
    }

    func testTheMoveTargetFollowsTheCall() {
        XCTAssertEqual(ScanGrader.result(of: steps(moveMs: 6000), flagCall: false, answer: answer(flagged: false)).detail.softMisses, [.moveSlow])
        XCTAssertEqual(ScanGrader.result(of: steps(moveMs: 6000), flagCall: true, answer: answer()).detail.softMisses, [])
        XCTAssertEqual(ScanGrader.result(of: steps(moveMs: 10_001), flagCall: true, answer: answer()).detail.softMisses, [.moveSlow])
    }

    func testTimingIsRecordOnly() {
        XCTAssertEqual(ScanTimedStep.allCases.map(ScanTiming.targetMs), [10_000, 5_000, 20_000, 15_000, 10_000])
        XCTAssertEqual(ScanTimedStep.allCases.compactMap(ScanTiming.limitMs), [])
        XCTAssertFalse(ScanTiming.isOverTarget(10_000, .quickScan)); XCTAssertTrue(ScanTiming.isOverTarget(10_001, .quickScan))
    }

    func testAttemptFromAnOutcomeAndASkip() {
        let outcome = ScanGrader.result(of: steps(played: "c4f7"), flagCall: true, answer: answer())
        let attempt = ScanAttempt(id: "a", puzzleId: "p", runId: "r", flagCall: true, outcome: outcome, playedAt: 9)
        XCTAssertEqual(attempt.result, .failed); XCTAssertEqual(attempt.mistakes, 1); XCTAssertEqual(attempt.flagCall, true)
        let skip = ScanAttempt.skip(id: "s", puzzleId: "p", runId: "r", playedAt: 9)
        XCTAssertEqual(skip.result, .skipped); XCTAssertNil(skip.flagCall); XCTAssertEqual(skip.mistakes, 0)
    }
}
