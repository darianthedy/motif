#if DEBUG
import XCTest
@testable import Motif

/// The capture fixtures D09's screenshot tests rely on (plan §8.4 capture issues).
final class CaptureFixtureTests: XCTestCase {
    /// S09m: the finished run has its results recorded, so session complete shows 2 solved, 1 missed.
    func testCompleteSeedFinishesTheRunWithResults() throws {
        var library = Library()
        CaptureSeed.apply("complete", to: &library)
        let run = try XCTUnwrap(runIn(library, "sample-solve"))
        let progress = progressOf(library, run)
        XCTAssertNil(progress.current)
        XCTAssertEqual(progress.solved, 2)
        XCTAssertEqual(progress.failed, 1)
    }
    func testNoticeTakesItsText() {
        XCTAssertEqual(CaptureFixture("capture,notice=Progress reset. Every puzzle is unseen again.")["notice"], "Progress reset. Every puzzle is unseen again.")
        XCTAssertEqual(CaptureFixture("notice")["notice"], "")
        XCTAssertTrue(CaptureFixture("seed=games,select,sidebar").has("sidebar"))
    }
}
#endif
