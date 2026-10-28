import Synchronization
import XCTest
@testable import Motif

/// A clock that only moves when the test advances it.
final class TestClock: AnalysisClock {
    private struct Sleeper { let deadline: Duration; let wake: CheckedContinuation<Void, Never> }
    private struct State { var now = Duration.zero; var sleepers: [Sleeper] = [] }
    private let state = Mutex(State())

    var now: Duration { state.withLock { $0.now } }

    func sleep(until deadline: Duration) async throws {
        await withCheckedContinuation { (wake: CheckedContinuation<Void, Never>) in
            let due = state.withLock { state in
                guard deadline > state.now else { return true }
                state.sleepers.append(Sleeper(deadline: deadline, wake: wake))
                return false
            }
            if due { wake.resume() }
        }
    }

    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now += duration
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }.map(\.wake)
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for wake in due { wake.resume() }
    }
}

/// The analyzer against `FakeEngine` and `TestClock`: no real engine, and no waiting
/// out real debounce or throttle time.
@MainActor final class AnalyzerTests: XCTestCase {
    private let go = "go depth 22 movetime 20000"
    private let mate = "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3"
    private let stalemate = "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"
    private let bareKings = "8/8/4k3/8/8/4K3/8/8 w - - 0 1"

    /// Distinct ordinary positions (the start position, numbered by its move field).
    private func position(_ number: Int, _ side: Side = .white) -> String {
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR \(side.rawValue) KQkq - 0 \(number)"
    }

    /// Lets resumed timers and engine output reach the main actor.
    private func settle() async { try? await Task.sleep(for: .milliseconds(50)) }

    private func eventually(_ message: String, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(2)) }
        XCTAssertTrue(condition(), message)
    }

    private func gos(_ engine: FakeEngine) -> Int { engine.sent.filter { $0.hasPrefix("go") }.count }

    /// Shows `fen` and lets the debounce pass, so its search is running.
    private func search(_ fen: String, _ analyzer: Analyzer, _ engine: FakeEngine, _ clock: TestClock) async {
        let before = gos(engine)
        analyzer.show(fen: fen)
        clock.advance(by: Analyzer.debounce)
        await eventually("search for \(fen) started") { gos(engine) == before + 1 }
    }

    func testRapidStepsStopOnceAndSearchOnlyTheLastPosition() async {
        let engine = FakeEngine(), clock = TestClock(), analyzer = Analyzer(engine: engine, clock: clock)
        await search(position(1), analyzer, engine, clock)
        XCTAssertEqual(engine.sent, ["position fen \(position(1))", go])

        for number in 2...6 {
            analyzer.show(fen: position(number))
            clock.advance(by: .milliseconds(50))
            await settle()
        }
        XCTAssertEqual(engine.sent.count, 3, "nothing but the stop until the debounce passes: \(engine.sent)")
        clock.advance(by: Analyzer.debounce)
        await eventually("the last position is searched") { engine.sent.count == 5 }
        await settle()
        XCTAssertEqual(engine.sent, ["position fen \(position(1))", go, "stop", "position fen \(position(6))", go])
    }

    func testNextSearchWaitsForTheStoppedSearchsBestmove() async {
        let engine = FakeEngine(answersStop: false), clock = TestClock(), analyzer = Analyzer(engine: engine, clock: clock)
        await search(position(1), analyzer, engine, clock)
        analyzer.show(fen: position(2))
        clock.advance(by: Analyzer.debounce * 4)
        await settle()
        XCTAssertEqual(engine.sent.last, "stop")
        XCTAssertEqual(gos(engine), 1, "go sent while the engine was still searching")

        engine.emit("bestmove e2e4")
        await eventually("the next search starts once the engine is idle") { gos(engine) == 2 }
        XCTAssertEqual(Array(engine.sent.suffix(3)), ["stop", "position fen \(position(2))", go])
    }

    func testLinesFromAStoppedSearchNeverReachTheEvaluation() async {
        let engine = FakeEngine(answersStop: false), clock = TestClock(), analyzer = Analyzer(engine: engine, clock: clock)
        await search(position(1), analyzer, engine, clock)
        engine.emit("info depth 5 score cp 30 pv e2e4")
        await eventually("partial result published") { analyzer.evaluation?.depth == 5 }

        analyzer.show(fen: position(2, .black))
        XCTAssertNil(analyzer.evaluation, "nothing known yet for the new position")
        engine.emit("info depth 6 score cp 999 pv e2e4")
        await settle()
        XCTAssertNil(analyzer.evaluation)

        engine.emit("bestmove e2e4")
        clock.advance(by: Analyzer.debounce)
        await eventually("second search started") { gos(engine) == 2 }
        engine.emit("info depth 3 score cp 40 pv e7e5")
        await eventually("new search's result published") { analyzer.evaluation?.depth == 3 }
        XCTAssertEqual(analyzer.evaluation, Evaluation(fen: position(2, .black), depth: 3, score: .cp(-40), final: false))

        // Back to the first position: its cached partial, untouched by the stopped search's line.
        analyzer.show(fen: position(1))
        XCTAssertEqual(analyzer.evaluation, Evaluation(fen: position(1), depth: 5, score: .cp(30), final: false))
    }

    func testCachedPositionAtTargetDepthNeedsNoSearch() async {
        let engine = FakeEngine(), clock = TestClock(), analyzer = Analyzer(engine: engine, clock: clock)
        await search(position(1), analyzer, engine, clock)
        engine.emit("info depth 22 score cp 15 pv e2e4")
        engine.emit("bestmove e2e4")
        await eventually("search finished") { analyzer.evaluation?.final == true }

        analyzer.show(fen: position(2))
        analyzer.show(fen: position(1))
        XCTAssertEqual(analyzer.evaluation, Evaluation(fen: position(1), depth: 22, score: .cp(15), final: true))
        clock.advance(by: Analyzer.debounce * 4)
        await settle()
        XCTAssertEqual(gos(engine), 1)
    }

    func testPartialUpdatesAreThrottled() async {
        let engine = FakeEngine(), clock = TestClock(), analyzer = Analyzer(engine: engine, clock: clock)
        await search(position(1), analyzer, engine, clock)
        engine.emit("info depth 1 score cp 10 pv e2e4")
        await eventually("first update is immediate") { analyzer.evaluation?.depth == 1 }
        engine.emit("info depth 2 score cp 20 pv e2e4")
        engine.emit("info depth 3 score cp 30 pv e2e4")
        await settle()
        XCTAssertEqual(analyzer.evaluation?.depth, 1)
        clock.advance(by: Analyzer.throttle)
        await eventually("the newest update follows at the end of the window") { analyzer.evaluation?.depth == 3 }
    }

    func testCheckmateStalemateAndBareKingsNeedNoEngine() async {
        let engine = FakeEngine(), clock = TestClock(), analyzer = Analyzer(engine: engine, clock: clock)
        analyzer.show(fen: mate)
        XCTAssertEqual(analyzer.evaluation, Evaluation(fen: mate, depth: 0, score: .mate(0), final: true))
        XCTAssertEqual(analyzer.evaluation?.winner, .black)
        analyzer.show(fen: stalemate)
        XCTAssertEqual(analyzer.evaluation?.score, .cp(0))
        analyzer.show(fen: bareKings)
        XCTAssertEqual(analyzer.evaluation?.score, .cp(0))
        clock.advance(by: Analyzer.debounce * 4)
        await settle()
        XCTAssertEqual(engine.sent, [])
    }

    func testLeavingActiveStopsAndComingBackResumes() async {
        let engine = FakeEngine(), clock = TestClock(), analyzer = Analyzer(engine: engine, clock: clock)
        await search(position(1), analyzer, engine, clock)
        analyzer.pause()
        XCTAssertEqual(engine.sent.last, "stop")
        analyzer.show(fen: position(2))
        clock.advance(by: Analyzer.debounce * 4)
        await settle()
        XCTAssertEqual(gos(engine), 1, "no search while inactive")

        analyzer.resume()
        clock.advance(by: Analyzer.debounce)
        await eventually("the current position is searched again") { gos(engine) == 2 }
        XCTAssertEqual(Array(engine.sent.suffix(2)), ["position fen \(position(2))", go])
    }

    func testHiddenBarStopsAndStartsNothing() async {
        let engine = FakeEngine(), clock = TestClock(), analyzer = Analyzer(engine: engine, clock: clock)
        await search(position(1), analyzer, engine, clock)
        analyzer.enabled = false
        XCTAssertEqual(engine.sent.last, "stop")
        analyzer.show(fen: position(2))
        clock.advance(by: Analyzer.debounce * 4)
        await settle()
        XCTAssertEqual(gos(engine), 1)
    }

    func testThreeLinesAskForMultiPVAndArriveRanked() async {
        let engine = FakeEngine(), clock = TestClock(), analyzer = Analyzer(engine: engine, clock: clock)
        analyzer.lineCount = 3
        await search(position(1), analyzer, engine, clock)
        XCTAssertEqual(engine.sent, ["setoption name MultiPV value 3", "position fen \(position(1))", go])
        engine.emit("info depth 22 multipv 2 score cp 10 pv d2d4 d7d5")
        engine.emit("info depth 22 multipv 1 score cp 30 pv e2e4 e7e5")
        engine.emit("info depth 22 multipv 3 score cp -5 pv g1f3")
        engine.emit("bestmove e2e4")
        await eventually("search finished") { analyzer.evaluation?.final == true }
        XCTAssertEqual(analyzer.lines.map(\.moves), [["e2e4", "e7e5"], ["d2d4", "d7d5"], ["g1f3"]])
        XCTAssertEqual(analyzer.evaluation?.score, .cp(30), "the bar follows the best line")

        analyzer.lineCount = 1
        XCTAssertEqual(analyzer.lines.map(\.moves), [["e2e4", "e7e5"]], "fewer lines come from the cache")
        clock.advance(by: Analyzer.debounce * 4)
        await settle()
        XCTAssertEqual(gos(engine), 1, "no new search for fewer lines")
    }

    func testAskingForMoreLinesSearchesAgain() async {
        let engine = FakeEngine(), clock = TestClock(), analyzer = Analyzer(engine: engine, clock: clock)
        await search(position(1), analyzer, engine, clock)
        engine.emit("info depth 22 score cp 15 pv e2e4")
        engine.emit("bestmove e2e4")
        await eventually("search finished") { analyzer.evaluation?.final == true }
        XCTAssertEqual(analyzer.lines.count, 1)

        analyzer.lineCount = 3
        clock.advance(by: Analyzer.debounce)
        await eventually("searched again for three lines") { gos(engine) == 2 }
        XCTAssertEqual(Array(engine.sent.suffix(3)), ["setoption name MultiPV value 3", "position fen \(position(1))", go])
    }
}
