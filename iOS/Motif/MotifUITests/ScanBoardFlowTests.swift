import XCTest

/// Scan plan S03: in `.markSquares` a tap only marks, and nothing moves a piece.
final class ScanBoardFlowTests: FlowTestCase {
    func testTapsMarkAndNeverMovePieces() {
        launch("scan-board")
        tap("e4")
        XCTAssertTrue(square("e4").label.hasSuffix("White Pawn, marked"), square("e4").label)
        // A tap on a piece then a legal square marks both and moves nothing.
        tap("f3"); tap("g5")
        XCTAssertEqual(square("g5").label, "g5, empty, marked")
        XCTAssertTrue(square("f3").label.hasPrefix("f3, White Knight"))
        tap("g5"); tap("f3")
        XCTAssertEqual(square("g5").label, "g5, empty")
        XCTAssertEqual(square("f3").label, "f3, White Knight")
        // A drag moves nothing either.
        drag("f3", "g5")
        XCTAssertEqual(square("f3").label, "f3, White Knight")
        XCTAssertEqual(square("g5").label, "g5, empty")
    }
    func testCheckShowsCorrectExtraAndMissedRings() {
        launch("scan-board")
        tap("e4"); tap("a7")
        button("scan-board-check").tap()
        XCTAssertEqual(square("e4").label, "e4, White Pawn, marked, correct")
        XCTAssertEqual(square("a7").label, "a7, Black Pawn, marked, not in the answer")
        button("scan-board-check").tap()
        tap("c4"); button("scan-board-check").tap()
        XCTAssertEqual(square("e4").label, "e4, White Pawn, missed")
    }
}
