import XCTest

/// Scan plan S03 and S07: in `.markSquares`, `.markTargets` and `.drawArrows` a tap or a drag only
/// calls its own callback, and nothing moves a piece; the two-tap arrow equals the drag.
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

    func testTargetsTapAndDragMarkAndNeverMovePieces() {
        launch("scan-board:targets")
        let e4 = square("e4")
        tap(e4, until: "label == 'e4, White Pawn, marked orange, attacked as often as defended'")
        tap(e4, until: "label == 'e4, White Pawn, marked red, loses material'")
        tap(e4, until: "label == 'e4, White Pawn'")
        tap(square("e7"), until: "label == 'e7, empty, dot'")
        // One drag along the third rank: the same as tapping each square it crosses.
        slowDrag("d3", "h3")
        expect(square("g3"), "label == 'g3, empty, dot'")
        XCTAssertEqual(square("d3").label, "d3, empty, dot")
        XCTAssertEqual(square("f3").label, "f3, White Knight, marked orange, attacked as often as defended")
        XCTAssertEqual(square("h3").label, "h3, empty, dot")
        XCTAssertEqual(square("g5").label, "g5, empty")
        capture("scan-board-targets")
    }
    func testArrowsByDragOrTwoTapsDeletedByTapOrList() {
        launch("scan-board:arrows")
        let arrow = button("scan-arrow-f3g5")
        slowDrag("f3", "g5"); wait(arrow)
        XCTAssertTrue(arrow.label.hasSuffix("yours"), arrow.label)
        XCTAssertTrue(square("f3").label.hasPrefix("f3, White Knight")); XCTAssertEqual(square("g5").label, "g5, empty")
        // A tap on the shaft, between the two squares, deletes it.
        let from = square("f3").frame, to = square("g5").frame
        // From the square, not the app: the app's coordinates don't follow a landscape window (iPhone Duo, IL).
        square("f3").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: (to.midX - from.midX) / 2, dy: (to.midY - from.midY) / 2)).tap()
        expect(arrow, "exists == false")
        // Two taps draw the same arrow; the list deletes it.
        tap(square("f3"), until: "isSelected == true")
        tap(square("g5"), until: "isSelected == false", on: square("f3"))
        wait(arrow); XCTAssertTrue(square("f3").label.hasPrefix("f3, White Knight"))
        capture("scan-board-arrows")
        arrow.tap(); expect(arrow, "exists == false")
        // Black's knight draws their arrow; an empty square starts none.
        slowDrag("f6", "e4")
        let theirs = button("scan-arrow-f6e4"); wait(theirs); XCTAssertTrue(theirs.label.hasSuffix("theirs"), theirs.label)
        tap("d3"); XCTAssertFalse(square("d3").isSelected)
    }
    /// Slow enough that the drag reports every square it crosses.
    private func slowDrag(_ from: String, _ to: String) {
        XCTAssertTrue(square(from).waitForExistence(timeout: 10))
        square(from).press(forDuration: 0.1, thenDragTo: square(to), withVelocity: .slow, thenHoldForDuration: 0.1)
    }
}
