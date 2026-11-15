import XCTest
@testable import Motif

/// The game list row: details on the second line, the opening on its own third line.
final class GameRowTests: XCTestCase {
    func testOpeningMovesOutOfTheDetailsLine() {
        let headers = readHeaders("""
        [Event "4NCL"]
        [Round "1.11"]
        [Date "2016.11.19"]
        [White "Howell, David"]
        [Black "Quinn, John M"]
        [ECO "A48"]
        [Opening "London E – KID: h3, a4, Qb3"]

        1. d4 *
        """)
        XCTAssertEqual(gameDetails(headers), "4NCL · Round 1.11 · 2016.11.19")
        XCTAssertEqual(gameOpening(headers), "London E – KID: h3, a4, Qb3")
    }
    func testOpeningFallsBackToECOAndSkipsUnknowns() {
        XCTAssertEqual(gameOpening(readHeaders("[Opening \"?\"]\n[ECO \"A48\"]\n\n*")), "A48")
        XCTAssertNil(gameOpening(readHeaders("[ECO \"?\"]\n\n*")))
    }
}
