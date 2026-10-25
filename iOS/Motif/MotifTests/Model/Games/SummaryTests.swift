import XCTest
@testable import Motif

/// One case for every summary.test.ts case.
final class SummaryTests: XCTestCase {
    func testNamesItByItsPlayers() {
        XCTAssertEqual(gameTitle(PgnHeaders([("White", "Carlsen"), ("Black", "Nakamura")])), "Carlsen – Nakamura")
        XCTAssertEqual(gameTitle(PgnHeaders([("White", "Carlsen"), ("Black", "?")])), "Carlsen – ?")
    }
    func testFallsBackToTheEventThenToNothingKnown() {
        XCTAssertEqual(gameTitle(PgnHeaders([("White", "?"), ("Black", "?"), ("Event", "Endgame study")])), "Endgame study")
        XCTAssertEqual(gameTitle(PgnHeaders([("White", "?"), ("Event", "?")])), "Untitled game")
    }
    func testSaysWhatElseIsKnownUnderneath() {
        XCTAssertEqual(gameSubtitle(PgnHeaders([("White", "A"), ("Result", "1-0"), ("Event", "Open"),
                                                ("ECO", "C65"), ("Date", "2024.03.??")])), "1-0 · Open · C65 · 2024.03")
        XCTAssertEqual(gameSubtitle(PgnHeaders([("Result", "*"), ("Date", "????.??.??")])), "")
        XCTAssertEqual(gameSubtitle(PgnHeaders([("Event", "Open"), ("Result", "0-1")])), "0-1")
    }
    func testMatchesEveryWordInAnyHeaderIgnoringCase() {
        let headers = PgnHeaders([("White", "Magnus Carlsen"), ("Black", "Hikaru Nakamura"), ("Event", "Tata Steel")])
        XCTAssertTrue(matchesSearch(headers, "carlsen tata"))
        XCTAssertFalse(matchesSearch(headers, "carlsen open"))
        XCTAssertTrue(matchesSearch(headers, "  "))
    }
    func testLeavesOutClockAndEvalCommands() {
        XCTAssertEqual(displayComment("[%clk 0:03:12] Good move [%eval 0.4]"), "Good move")
        XCTAssertEqual(displayComment(nil), "")
    }
}
