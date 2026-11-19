import XCTest
@testable import Motif

/// The derive rules over scan attempts: the same behaviour as the Puzzles tab.
final class ScanDeriveTests: XCTestCase {
    private var clock: Int64 = 0
    private func attempt(_ puzzleId: String, _ result: AttemptResult, runId: String? = "run") -> ScanAttempt {
        clock += 1
        return testScanAttempt("a\(clock)", puzzleId, result, runId: runId, playedAt: clock)
    }
    private func library(_ n: Int) -> Library {
        var library = Library()
        library.scanPuzzles = (0..<n).map { testScanPuzzle("s\($0)", addedAt: Int64($0)) }
        return library
    }
    private func run(_ ids: [String]) -> Run { Run(id: "run", scope: SCOPE_ALL, mode: .randomGlobal, queue: ids, startedAt: 0) }

    /// Playtest 3: a pass that missed an arrow goes to To review, not Solved; a pass with only a
    /// quick-scan miss or a slow step stays solved, and so does an older pass whose only misses
    /// were targets (no longer graded, v6). It isn't retried in the run.
    func testAPassWithArrowMissesIsToReview() {
        var lib = library(5); let r = run((0..<5).map { "s\($0)" }); lib.scanRuns = [r]
        func passed(_ id: String, _ soft: [ScanSoftMiss]) -> ScanAttempt {
            var a = attempt(id, .solved); a.detail.softMisses = soft; return a
        }
        lib.scanAttempts = [passed("s0", [.targetsMissed]), passed("s1", [.arrowsMissed, .moveSlow]),
                            passed("s2", [.quickScanMissed]), passed("s3", [.quickScanSlow]), attempt("s4", .failed)]
        XCTAssertEqual(scanReviewIds(lib), ["s1", "s4"])
        XCTAssertEqual(scanStats(lib), Stats(total: 5, solved: 3, failed: 2, unseen: 0))
        XCTAssertEqual(lib.scanAttempts.map(\.mistakes), [0, 0, 0, 0, 1], "still not a mistake")
        XCTAssertEqual(scanProgressOf(lib, r).solved, 4, "a pass is a pass in the run")
        lib.scanAttempts.append(attempt("s1", .solved))
        XCTAssertEqual(scanReviewIds(lib), ["s4"], "a clean pass clears it")
    }

    func testResumesWhereTheRunGotToFromItsAttempts() {
        var lib = library(3); let r = run(["s0", "s1", "s2"]); lib.scanRuns = [r]
        lib.scanAttempts = [attempt("s0", .solved)]
        let progress = scanProgressOf(lib, r)
        XCTAssertEqual(progress.current, "s1"); XCTAssertEqual(progress.remaining, 2)
        XCTAssertTrue(scanResumable(lib, SCOPE_ALL)); XCTAssertFalse(scanResumable(lib, SCOPE_REVIEW))
    }

    func testAFailComesBackAfterTheGapAndASkipDoesNot() {
        let ids = (0..<6).map { "s\($0)" }
        var lib = library(6); let r = run(ids); lib.scanRuns = [r]
        lib.scanAttempts = [attempt("s0", .failed), attempt("s1", .skipped)]
            + ["s2", "s3"].map { attempt($0, .solved) }
        XCTAssertEqual(scanProgressOf(lib, r).current, "s4")
        lib.scanAttempts.append(attempt("s4", .solved))
        XCTAssertEqual(scanProgressOf(lib, r).current, "s0", "retry after RETRY_GAP")
        lib.scanAttempts.append(attempt("s0", .solved)); lib.scanAttempts.append(attempt("s5", .solved))
        XCTAssertNil(scanProgressOf(lib, r).current)
        XCTAssertFalse(scanResumable(lib, SCOPE_ALL))
    }

    /// Playtest 2: the counter and bar move after every finished puzzle, and a fail's retry adds one.
    func testTheCounterMovesAfterAFailAndTheRetryAddsToTheTotal() {
        var lib = library(2); let r = run(["s0", "s1"]); lib.scanRuns = [r]
        XCTAssertEqual(scanPositionOf(lib, r), RunPosition(done: 0, total: 2))
        XCTAssertEqual(scanPositionOf(lib, r).number, 1)
        lib.scanAttempts = [attempt("s0", .failed)]
        let afterFail = scanPositionOf(lib, r)
        XCTAssertEqual(afterFail.number, 2); XCTAssertEqual(afterFail.total, 3, "Puzzle 2 of 3")
        XCTAssertEqual(afterFail.fraction, 1.0 / 3, accuracy: 1e-9)
        lib.scanAttempts.append(attempt("s1", .solved))
        XCTAssertEqual(scanPositionOf(lib, r).number, 3); XCTAssertEqual(scanPositionOf(lib, r).total, 3)
        lib.scanAttempts.append(attempt("s0", .solved))
        XCTAssertEqual(scanPositionOf(lib, r), RunPosition(done: 3, total: 3))
        XCTAssertEqual(scanPositionOf(lib, r).fraction, 1)
        // A skip moves the counter too, with no retry.
        var skip = library(2); skip.scanRuns = [r]; skip.scanAttempts = [attempt("s0", .skipped)]
        XCTAssertEqual(scanPositionOf(skip, r), RunPosition(done: 1, total: 2))
    }

    func testADeletedPuzzleDropsOutOfTheRun() {
        var lib = library(3); let r = run(["s0", "s1", "s2"]); lib.scanRuns = [r]
        lib.scanPuzzles.removeAll { $0.id == "s0" }
        XCTAssertEqual(scanProgressOf(lib, r).queue, ["s1", "s2"]); XCTAssertEqual(scanProgressOf(lib, r).current, "s1")
    }

    func testTwoDevicesOnOneRunServeEachPuzzleOnce() {
        var lib = library(2); let r = run(["s0", "s1"]); lib.scanRuns = [r]
        // Both devices played s0 before seeing each other's attempt.
        lib.scanAttempts = [attempt("s0", .solved), attempt("s0", .solved)]
        let progress = scanProgressOf(lib, r)
        XCTAssertEqual(progress.current, "s1"); XCTAssertEqual(progress.played, 2); XCTAssertEqual(progress.solved, 1)
    }

    func testReviewHoldsOnlyPuzzlesWhoseLatestResultFailed() {
        var lib = library(4)
        lib.scanAttempts = [attempt("s0", .failed), attempt("s1", .failed), attempt("s1", .solved),
                            attempt("s2", .skipped), attempt("s3", .failed), attempt("s3", .skipped)]
        XCTAssertEqual(scanReviewIds(lib), ["s0", "s3"])
        XCTAssertEqual(scanStats(lib), Stats(total: 4, solved: 1, failed: 2, unseen: 1))
        XCTAssertEqual(Set(scanQueue(lib, .reviewMistakes)), ["s0", "s3"])
    }

    func testTheWholePoolDrawPutsRecentPuzzlesLast() {
        var lib = library(4); lib.scanAttempts = [attempt("s1", .solved)]
        let queue = scanQueue(lib, .randomGlobal)
        XCTAssertEqual(Set(queue), ["s0", "s1", "s2", "s3"]); XCTAssertEqual(queue.last, "s1")
    }

    func testPoolIsInArrivalOrder() {
        var lib = Library()
        lib.scanPuzzles = [testScanPuzzle("b", addedAt: 2), testScanPuzzle("c", addedAt: 1), testScanPuzzle("a", addedAt: 2)]
        XCTAssertEqual(scanPool(lib).map(\.id), ["c", "a", "b"])
    }

    func testScanAndPuzzleProgressStayApart() {
        var lib = testDataLibrary(); lib.scanPuzzles = [testScanPuzzle("p1")]
        lib.attempts = [testDataAttempt()]
        XCTAssertEqual(scanStats(lib).unseen, 1)
        lib.scanAttempts = [attempt("p1", .failed)]
        XCTAssertEqual(statusOf(puzzleRecords(lib.attempts), "p1"), .solved)
    }
}
