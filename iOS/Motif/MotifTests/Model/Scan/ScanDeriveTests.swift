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
