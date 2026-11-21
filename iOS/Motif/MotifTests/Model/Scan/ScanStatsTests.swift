import XCTest
@testable import Motif

/// Scan plan §8 (S10): Stats from the attempts and the pool, and the Markdown export for Caïssa.
final class ScanStatsTests: XCTestCase {
    private let week: Int64 = 7 * 24 * 60 * 60 * 1000
    /// Weeks start on Monday in UTC, so grouping doesn't depend on where the tests run.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!; calendar.firstWeekday = 2
        return calendar
    }()
    /// Monday 2026-11-02 00:00 UTC.
    private let monday: Int64 = 1_793_577_600_000

    /// A flagged puzzle with a full scan: several quick-scan kinds and arrow kinds.
    private func fullPuzzle(_ id: String = "full") -> ScanPuzzle {
        var content = testScanContent("e1d1", scores: ["e8e7": 250])
        content.answer.quickScan = [ScanSquare(square: "d1", kind: .attacked), ScanSquare(square: "d8", kind: .opened),
                                    ScanSquare(square: "e8", kind: .undefended)]
        content.answer.arrows = [ScanArrow(from: "d1", to: "d2", side: .theirs, kind: .threat),
                                 ScanArrow(from: "e8", to: "d8", side: .own, kind: .check)]
        return ScanPuzzle(id: id, content: content, addedAt: 0)
    }
    private func quietPuzzle(_ id: String = "quiet") -> ScanPuzzle {
        ScanPuzzle(id: id, content: testScanContent("e1f1", flagged: false, quickScan: []), addedAt: 1)
    }
    private func attempt(_ id: String, _ puzzle: String, _ result: AttemptResult = .solved, flagCall: Bool? = true,
                         at: Int64 = 0, steps: ScanSteps = ScanSteps(), failReason: ScanFailReason? = nil) -> ScanAttempt {
        ScanAttempt(id: id, puzzleId: puzzle, runId: nil, result: result, flagCall: flagCall,
                    detail: ScanAttemptDetail(steps: steps, failReason: failReason), playedAt: monday + at)
    }
    private func library(_ puzzles: [ScanPuzzle], _ attempts: [ScanAttempt]) -> Library {
        var library = Library(); library.scanPuzzles = puzzles; library.scanAttempts = attempts; return library
    }
    private func quick(_ ms: Int, missed: [String] = []) -> ScanMarkStep { ScanMarkStep(ms: ms, missed: missed) }

    func testNothingPlayedHasNoFigures() {
        let stats = ScanStats(library([fullPuzzle()], [.skip(puzzleId: "full", runId: nil, playedAt: 1)]), calendar: calendar)
        XCTAssertEqual(stats.played, 0)
        XCTAssertNil(stats.quickScanMedianMs); XCTAssertNil(stats.flagAccuracy); XCTAssertNil(stats.mostMissed)
        XCTAssertEqual(stats.weeks, []); XCTAssertEqual(stats.recentFails, [])
        XCTAssertEqual(stats.flagShare, 1, "the pool's share counts with nothing played")
    }

    func testMedianAndFlagAccuracySkipSkipsAndCountANoCallAsWrong() {
        let attempts = [
            attempt("a", "full", steps: ScanSteps(quickScan: quick(6000))),
            attempt("b", "quiet", flagCall: false, steps: ScanSteps(quickScan: quick(9000))),
            attempt("c", "quiet", flagCall: true, steps: ScanSteps(quickScan: quick(7000))),   // Tactic on quiet: wrong
            attempt("d", "full", .failed, flagCall: nil, steps: ScanSteps(quickScan: ScanMarkStep(ms: 10_000, timedOut: true)), failReason: .noCall),
            .skip(puzzleId: "full", runId: nil, playedAt: monday),
            attempt("gone", "deleted"),
        ]
        let stats = ScanStats(library([fullPuzzle(), quietPuzzle()], attempts), calendar: calendar)
        XCTAssertEqual(stats.played, 4); XCTAssertEqual(stats.solved, 3)
        XCTAssertEqual(stats.quickScanMedianMs, 8000)
        XCTAssertEqual(stats.flagRight, 2); XCTAssertEqual(stats.flagAccuracy, 0.5)
        XCTAssertEqual(stats.poolSize, 2); XCTAssertEqual(stats.flagPuzzles, 1)
    }

    func testMissesCountByTheAnswersLabelsInStepsPlayed() {
        let full = ScanSteps(quickScan: quick(5000, missed: ["e8", "d8"]),
                             targets: ScanMarkStep(ms: 9000, missed: ["d7", "c6"]),   // Before v6: not counted
                             arrows: ScanMarkStep(ms: 9000, missed: ["d1d2"]))
        let attempts = [
            attempt("a", "full", steps: full),
            attempt("b", "full", steps: ScanSteps(quickScan: quick(5000, missed: ["e8"]))),   // No full scan: no targets expected
        ]
        let stats = ScanStats(library([fullPuzzle()], attempts), calendar: calendar)
        let tallies = Dictionary(uniqueKeysWithValues: stats.misses.map { ($0.category, ($0.missed, $0.expected)) })
        XCTAssertEqual(tallies[.quickScan(.undefended)]?.0, 2); XCTAssertEqual(tallies[.quickScan(.undefended)]?.1, 2)
        XCTAssertEqual(tallies[.quickScan(.opened)]?.0, 1); XCTAssertEqual(tallies[.quickScan(.attacked)]?.0, 0)
        XCTAssertEqual(tallies[.arrow(.threat)]?.0, 1); XCTAssertEqual(tallies[.arrow(.check)]?.0, 0)
        XCTAssertEqual(stats.mostMissed?.category, .quickScan(.undefended))
        // Same misses: the higher rate first (1 of 1 before 1 of 2), then the plan's order.
        let ones = stats.misses.filter { $0.missed == 1 }.map(\.category)
        XCTAssertEqual(ones, [.arrow(.threat), .quickScan(.opened)])
        XCTAssertFalse(stats.misses.contains { $0.category.step == "Targets" })
    }

    func testWeeksGroupByCalendarWeekAndKeepTheLastTwelve() {
        let day: Int64 = 24 * 60 * 60 * 1000
        var attempts = [
            attempt("a", "full", at: 0, steps: ScanSteps(quickScan: quick(8000))),
            attempt("b", "quiet", .failed, flagCall: true, at: 6 * day, steps: ScanSteps(quickScan: quick(4000))),   // Sunday
            attempt("c", "full", at: 7 * day, steps: ScanSteps(quickScan: quick(6000))),                              // next Monday
        ]
        var stats = ScanStats(library([fullPuzzle(), quietPuzzle()], attempts), calendar: calendar)
        XCTAssertEqual(stats.weeks.map(\.played), [2, 1])
        XCTAssertEqual(stats.weeks[0].start, Date(timeIntervalSince1970: TimeInterval(monday) / 1000))
        XCTAssertEqual(stats.weeks[0].quickScanMedianMs, 6000)
        XCTAssertEqual(stats.weeks[0].solvedRate, 0.5); XCTAssertEqual(stats.weeks[0].flagAccuracy, 0.5)
        attempts = (0..<15).map { attempt("w\($0)", "full", at: Int64($0) * week) }
        stats = ScanStats(library([fullPuzzle()], attempts), calendar: calendar)
        XCTAssertEqual(stats.weeks.count, ScanStats.weekCount)
        XCTAssertEqual(stats.weeks.first?.start, Date(timeIntervalSince1970: TimeInterval(monday + 3 * week) / 1000))
    }

    /// An attempt from before v6 still lists its target misses, unlabelled now the answer has none.
    func testRecentFailsNewestFirstWithWhatWentWrong() {
        var attempts = (0..<12).map { attempt("f\($0)", "full", .failed, flagCall: false, at: Int64($0), failReason: .missedFlag) }
        attempts.append(attempt("bad", "full", .failed, at: 100,
                                steps: ScanSteps(quickScan: quick(5000, missed: ["e8"]), targets: ScanMarkStep(ms: 1, missed: ["d1"]),
                                                 arrows: ScanMarkStep(ms: 1, missed: ["e8d8"]),
                                                 move: ScanMoveStep(ms: 1, played: Uci.parse("e8e7"), lossCp: 250)),
                                failReason: .badMove))
        let stats = ScanStats(library([fullPuzzle()], attempts), calendar: calendar)
        XCTAssertEqual(stats.recentFails.count, ScanStats.recentFailCount)
        let newest = stats.recentFails[0]
        XCTAssertEqual(newest.reason, "Ke7 lost 2.5")
        XCTAssertEqual(newest.lastMove, "1. Kd1 (e1d1)")
        XCTAssertEqual(newest.missed, ["quick scan e8 (undefended)", "targets d1", "arrows e8d8 (check)"])
        XCTAssertEqual(stats.recentFails[1].reason, "Quiet on a tactical position")
        XCTAssertEqual(stats.recentFails.last?.playedAt, monday + 3, "the two oldest drop out")
    }

    func testFailReasonsForTimeAndMate() {
        let puzzle = fullPuzzle()
        XCTAssertEqual(ScanFailSummary(attempt("a", "full", .failed, flagCall: nil, failReason: .noCall), puzzle).reason, "No call in time")
        XCTAssertEqual(ScanFailSummary(attempt("b", "full", .failed, failReason: .noMove), puzzle).reason, "No move in time")
        let mate = ScanSteps(move: ScanMoveStep(ms: 1, played: Uci.parse("e8d8"), lossCp: ScanAnswer.lostMateCp))
        XCTAssertEqual(ScanFailSummary(attempt("c", "full", .failed, steps: mate, failReason: .badMove), puzzle).reason, "Kd8 let a mate go")
    }

    func testExportReadsTheSameNumbers() {
        let attempts = [
            attempt("a", "full", steps: ScanSteps(quickScan: quick(7400, missed: ["e8"]))),
            attempt("b", "quiet", .failed, flagCall: true, at: 1, steps: ScanSteps(quickScan: quick(9000)), failReason: .badMove),
        ]
        let stats = ScanStats(library([fullPuzzle(), quietPuzzle()], attempts), calendar: calendar)
        let text = ScanStatsExport.markdown(stats, now: Date(timeIntervalSince1970: TimeInterval(monday) / 1000), calendar: calendar)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "# Motif Scan Training summary")
        XCTAssertTrue(lines.contains("Exported 2026-11-02. 2 puzzles played, 1 solved."), text)
        XCTAssertTrue(lines.contains("- Median quick scan: 8.2 s (target 10 s)"), text)
        XCTAssertTrue(lines.contains("- Call accuracy: 50 % (1 of 2 calls right)"), text)
        XCTAssertTrue(lines.contains("- Most missed: undefended pieces, 1 of 1 missed"), text)
        XCTAssertTrue(lines.contains("- Tactic puzzles in the pool: 50 % (1 of 2)"), text)
        XCTAssertTrue(lines.contains("| 2026-11-02 | 2 | 50 % | 8.2 s | 50 % |"), text)
        XCTAssertTrue(lines.contains("1. `\(scanTestFen)`, last move 1. Kf1 (e1f1): Failed."), text)
        XCTAssertTrue(text.hasSuffix("\n"))
    }

    func testTrendMetricValues() {
        let week = ScanWeek(start: .now, played: 4, solved: 3, flagRight: 2, quickScanMedianMs: 7400)
        XCTAssertEqual(ScanTrendMetric.quickScan.value(week), 7.4)
        XCTAssertEqual(ScanTrendMetric.solved.value(week), 75)
        XCTAssertEqual(ScanTrendMetric.flagAccuracy.value(week), 50)
        XCTAssertEqual(ScanTrendMetric.quickScan.target, 10); XCTAssertNil(ScanTrendMetric.solved.target)
        XCTAssertNil(ScanTrendMetric.quickScan.value(ScanWeek(start: .now, played: 1, solved: 1, flagRight: 1)))
    }
}
