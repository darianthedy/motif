import XCTest
@testable import Motif

/// Scan plan §10, Timing (S09): record-only for 14 days after the first attempt, then a step's
/// limit switches on once its median over the last 50 is under the target, and stays on; the
/// Time Limits switch and VoiceOver / Switch Control turn limits off.
final class ScanTimingTests: XCTestCase {
    private let day: Int64 = 24 * 60 * 60 * 1000

    /// A graded attempt with a quick scan and a move of the given times.
    private func attempt(_ at: Int64, quick: Int, move: Int = 3000, flagCall: Bool = false, result: AttemptResult = .solved) -> ScanAttempt {
        let steps = ScanSteps(quickScan: ScanMarkStep(ms: quick, missed: [], extra: []),
                              move: ScanMoveStep(ms: move, played: Uci.parse("e8d8"), lossCp: 0))
        return ScanAttempt(id: "a\(at)", puzzleId: "p", runId: nil, result: result, flagCall: flagCall,
                           detail: ScanAttemptDetail(steps: steps), playedAt: at)
    }

    func testRecordOnlyForTheFirstFourteenDays() {
        let fast = (0..<10).map { attempt(Int64($0), quick: 2000) }
        XCTAssertEqual(ScanTiming.earned(fast, now: 14 * day - 1), [])
        XCTAssertEqual(ScanTiming.earned(fast, now: 14 * day), [.quickScan, .quietMove])
        XCTAssertEqual(ScanTiming.earned([], now: 100 * day), [], "no attempts, no limits")
    }

    func testTheFourteenDaysCountFromTheFirstGradedAttempt() {
        let skip = ScanAttempt.skip(puzzleId: "p", runId: nil, playedAt: 0)
        let attempts = [skip, attempt(5 * day, quick: 2000)]
        XCTAssertEqual(ScanTiming.earned(attempts, now: 14 * day), [], "a skip doesn't start the clock")
        XCTAssertEqual(ScanTiming.earned(attempts, now: 19 * day), [.quickScan, .quietMove])
    }

    func testTheMedianMustBeUnderTheTarget() {
        // Medians exactly at the target (10 s, 5 s) aren't under it.
        let at = [attempt(0, quick: 9000, move: 4000), attempt(1, quick: 11_000, move: 6000)]
        XCTAssertEqual(ScanTiming.earned(at, now: 20 * day), [])
        let under = [attempt(0, quick: 9000, move: 4000), attempt(1, quick: 10_998, move: 5998)]
        XCTAssertEqual(ScanTiming.earned(under, now: 20 * day), [.quickScan, .quietMove])
    }

    func testTheMedianIsOverTheLastFifty() {
        // 50 slow, then 50 fast: the last 50 are all fast.
        let slow = (0..<50).map { attempt(Int64($0), quick: 15_000, move: 9000) }
        let fast = (50..<100).map { attempt(15 * day + Int64($0), quick: 4000, move: 9000) }
        XCTAssertEqual(ScanTiming.earned(slow, now: 20 * day), [])
        XCTAssertEqual(ScanTiming.earned(slow + fast.prefix(24), now: 20 * day), [], "26 slow of 50: median still slow")
        XCTAssertEqual(ScanTiming.earned(slow + fast.prefix(25), now: 20 * day), [.quickScan], "25 and 25: median 9.5 s")
    }

    func testALimitStaysOnOnceEarned() {
        // Fast when the 14 days end, slow ever since: the limit stays.
        let fast = (0..<5).map { attempt(Int64($0), quick: 3000, move: 9000) }
        let slow = (0..<60).map { attempt(15 * day + Int64($0), quick: 15_000, move: 9000) }
        XCTAssertEqual(ScanTiming.earned(fast + slow, now: 30 * day), [.quickScan])
        // Slow when the 14 days end, fast for a while after, slow again.
        let early = (0..<5).map { attempt(Int64($0), quick: 15_000, move: 9000) }
        let burst = (0..<10).map { attempt(15 * day + Int64($0), quick: 1000, move: 9000) }
        let late = (0..<60).map { attempt(16 * day + Int64($0), quick: 15_000, move: 9000) }
        XCTAssertEqual(ScanTiming.earned(early + burst + late, now: 30 * day), [.quickScan])
    }

    func testEachStepAndTheMoveFollowTheCall() {
        // Flag moves count toward the flagged move's 10 s, No Flag moves toward the quiet 5 s.
        let flagged = (0..<3).map { attempt(Int64($0), quick: 15_000, move: 7000, flagCall: true) }
        let quiet = (3..<6).map { attempt(Int64($0), quick: 15_000, move: 7000, flagCall: false) }
        XCTAssertEqual(ScanTiming.earned(flagged + quiet, now: 20 * day), [.flaggedMove])
    }

    func testTheSwitchTurnsLimitsOff() {
        let fast = [attempt(0, quick: 2000)]
        XCTAssertEqual(ScanTiming.limits(fast, now: 20 * day).limitMs(.quickScan), 10_000)
        XCTAssertNil(ScanTiming.limits(fast, now: 20 * day).limitMs(.arrows))
        XCTAssertEqual(ScanTiming.limits(fast, now: 20 * day, enabled: false), ScanLimits())
    }

    func testThePreferenceFollowsVoiceOverAndSwitchControlUntilSet() {
        XCTAssertTrue(ScanTimeLimitsPreference.enabled(stored: nil, voiceOver: false, switchControl: false))
        XCTAssertFalse(ScanTimeLimitsPreference.enabled(stored: nil, voiceOver: true, switchControl: false))
        XCTAssertFalse(ScanTimeLimitsPreference.enabled(stored: nil, voiceOver: false, switchControl: true))
        XCTAssertFalse(ScanTimeLimitsPreference.enabled(stored: false, voiceOver: false, switchControl: false))
        XCTAssertTrue(ScanTimeLimitsPreference.enabled(stored: true, voiceOver: true, switchControl: false), "turned on by hand")
    }

    func testMedian() {
        XCTAssertNil(ScanTiming.median([]))
        XCTAssertEqual(ScanTiming.median([3, 1, 2]), 2)
        XCTAssertEqual(ScanTiming.median([4, 1, 3, 2]), 2.5)
    }
}
