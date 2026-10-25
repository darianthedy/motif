import XCTest
@testable import Motif

/// One test for every derive.test.ts case (14).
final class DeriveTests: XCTestCase {
    private var clock: Int64 = 0
    private func attempt(_ puzzleId: String, _ result: AttemptResult, runId: String? = nil,
                         mistakes: Int? = nil, playedAt: Int64? = nil) -> Attempt {
        clock += 1
        return Attempt(id: "a\(clock)", puzzleId: puzzleId, runId: runId, result: result,
                       mistakes: mistakes ?? (result == .failed ? 1 : 0), hinted: false,
                       playedAt: playedAt ?? clock)
    }
    private func makeRun(_ ids: [String]) -> Run {
        Run(id: "run", scope: "c", mode: .ordered, queue: ids, startedAt: 0)
    }
    private func play(_ run: Run, answer: (String, Int) -> AttemptResult) -> (served: [String], progress: RunProgress) {
        var attempts: [Attempt] = []
        let existing = Set(run.queue)
        var served: [String] = []
        var progress = runProgress(run, attempts, existing)
        while let current = progress.current {
            served.append(current)
            attempts.append(attempt(current, answer(current, served.count), runId: run.id))
            progress = runProgress(run, attempts, existing)
            if served.count > 1000 { XCTFail("Run never finishes"); break }
        }
        return (served, progress)
    }
    func testFollowsTheLatestResultThatWasNotASkip() {
        let records = puzzleRecords([attempt("a", .failed), attempt("a", .solved), attempt("a", .skipped),
                                     attempt("b", .solved), attempt("b", .failed, mistakes: 3), attempt("c", .skipped)])
        XCTAssertEqual(statusOf(records, "a"), .solved)
        XCTAssertEqual(statusOf(records, "b"), .failed)
        XCTAssertEqual(statusOf(records, "c"), .unseen)
        XCTAssertEqual(statusOf(records, "d"), .unseen)
        XCTAssertEqual(records["a"]?.attempts, 2)
        XCTAssertEqual(records["a"]?.mistakes, 1)
        XCTAssertEqual(records["b"]?.attempts, 2)
        XCTAssertEqual(records["b"]?.mistakes, 3)
    }
    func testReadsAttemptsInTheOrderPlayedNotReceived() {
        let late = attempt("a", .failed)
        let early = attempt("a", .solved, playedAt: late.playedAt - 1)
        XCTAssertEqual(statusOf(puzzleRecords([late, early]), "a"), .failed)
    }
    func testCollectsTheReviewSetAndStats() {
        let records = puzzleRecords([attempt("p1", .failed), attempt("p2", .solved), attempt("p3", .failed)])
        XCTAssertEqual(reviewIds(testIds(4), records), ["p1", "p3"])
        XCTAssertEqual(statsFor(testIds(4), records), Stats(total: 4, solved: 1, failed: 2, unseen: 1))
    }
    func testListsRecentlyPlayedPuzzlesNewestFirstSkipsIncluded() {
        XCTAssertEqual(recentIds([attempt("a", .solved), attempt("b", .skipped), attempt("a", .failed)]), ["a", "b"])
        let many = testIds(RECENT_MEMORY + 5).map { attempt($0, .solved) }
        XCTAssertEqual(recentIds(many).count, RECENT_MEMORY)
        XCTAssertEqual(recentIds(many).first, "p\(RECENT_MEMORY + 4)")
    }
    func testServesTheQueueInOrderAndFinishes() {
        let run = makeRun(testIds(3))
        let start = runProgress(run, [], Set(run.queue))
        XCTAssertEqual(start.current, "p0"); XCTAssertEqual(start.remaining, 3); XCTAssertEqual(start.progress, 0)
        let (served, progress) = play(run) { _, _ in .solved }
        XCTAssertEqual(served, testIds(3))
        XCTAssertNil(progress.current); XCTAssertEqual(progress.remaining, 0)
        XCTAssertEqual(progress.solved, 3); XCTAssertEqual(progress.progress, 1)
    }
    func testBringsAMissBackOnceAfterTheGap() {
        let (served, progress) = play(makeRun(testIds(6))) { id, _ in id == "p0" ? .failed : .solved }
        XCTAssertEqual(served, ["p0"] + Array(testIds(6).dropFirst().prefix(RETRY_GAP)) + ["p0", "p4", "p5"])
        XCTAssertEqual(progress.solved, 5); XCTAssertEqual(progress.failed, 1); XCTAssertNil(progress.current)
    }
    func testDoesNotBringARetryBackASecondTime() {
        let (served, _) = play(makeRun(testIds(5))) { id, _ in id == "p0" ? .failed : .solved }
        XCTAssertEqual(served.filter { $0 == "p0" }.count, 2)
    }
    func testServesWaitingRetriesEarlyOnceTheQueueRunsOut() {
        let (served, _) = play(makeRun(testIds(2))) { _, n in n <= 2 ? .failed : .solved }
        XCTAssertEqual(served, ["p0", "p1", "p0", "p1"])
    }
    func testCapsTheRetriesWaiting() {
        let run = makeRun(testIds(MAX_RETRIES + 2))
        let attempts = run.queue.map { attempt($0, .failed, runId: run.id) }
        let progress = runProgress(run, attempts, Set(run.queue))
        XCTAssertEqual(progress.remaining, MAX_RETRIES)
        XCTAssertEqual(progress.current, "p0")
        XCTAssertEqual(progress.failed, MAX_RETRIES + 2)
    }
    func testFinishesASkippedPuzzleWithoutCountingIt() {
        let (served, progress) = play(makeRun(testIds(2))) { id, _ in id == "p0" ? .skipped : .solved }
        XCTAssertEqual(served, ["p0", "p1"])
        XCTAssertEqual(progress.solved, 1); XCTAssertEqual(progress.failed, 0)
        XCTAssertEqual(progress.progress, 0.5); XCTAssertEqual(progress.played, 2)
    }
    func testASkippedRetryDoesNotComeBack() {
        let (served, _) = play(makeRun(testIds(5))) { id, n in id == "p0" ? (n == 1 ? .failed : .skipped) : .solved }
        XCTAssertEqual(served.filter { $0 == "p0" }.count, 2)
    }
    func testDropsPuzzlesDeletedSinceTheRunStarted() {
        let progress = runProgress(makeRun(testIds(3)), [], ["p0", "p2"])
        XCTAssertEqual(progress.queue, ["p0", "p2"])
        XCTAssertEqual(progress.remaining, 2)
    }
    func testIgnoresAttemptsMadeOutsideTheRun() {
        let run = makeRun(testIds(2))
        XCTAssertEqual(runProgress(run, [attempt("p0", .solved)], Set(run.queue)).current, "p0")
    }
    func testCountsPuzzlesPlayedOnTwoDevicesAtOnce() {
        let run = makeRun(testIds(3))
        let progress = runProgress(run, [attempt("p0", .solved, runId: "run"), attempt("p0", .failed, runId: "run"),
                                         attempt("p1", .solved, runId: "run")], Set(run.queue))
        XCTAssertEqual(progress.current, "p2")
        XCTAssertEqual(progress.solved, 2); XCTAssertEqual(progress.failed, 0)
    }
}
