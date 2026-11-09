import XCTest
@testable import Motif

/// `BoardLayout` against the canvas numbers (`boardGeom` in design/iphone-duo/kit.js) for
/// each §3 size. Containers are the content inside the safe area and the bars, measured
/// on the device in §8.1, less the 54 pt the side-bar poses spend on the inline title.
final class BoardLayoutTests: XCTestCase {
    private func layout(_ width: CGFloat, _ height: CGFloat, compact: Bool, eval: Bool) -> BoardLayout {
        BoardLayout(container: CGSize(width: width, height: height), compact: compact, evalBar: eval)
    }

    // O: 466 × 678, 382 wide inside the side bar (decision 5).
    func testClosedStacksAtTheFullWidth() {
        let on = layout(382, 590, compact: true, eval: true), off = layout(382, 590, compact: true, eval: false)
        XCTAssertEqual(on.mode, .stack); XCTAssertEqual(off.mode, .stack)
        XCTAssertEqual(on.board, 328); XCTAssertEqual(off.board, 350)
        XCTAssertEqual(on.evalFrame?.maxX ?? 0, on.boardFrame.minX - on.evalGap, accuracy: 0.01)
        XCTAssertNil(off.evalFrame)
        XCTAssertEqual(on.column.minY, on.boardFrame.maxY + BoardLayout.stackGap)
        XCTAssertEqual(on.column.height, 234, accuracy: 0.01)
        XCTAssertTrue(on.short, "O is a short column: lines replace the moves")
    }

    // O with the case-gap setting: 457 wide, 9 pt less for the board.
    func testClosedWithTheCaseGap() {
        XCTAssertEqual(layout(373, 590, compact: true, eval: true).board, 319)
        XCTAssertEqual(layout(373, 590, compact: true, eval: false).board, 341)
    }

    // SV: 469 × 669, 371.5 between the side bar and the inner strip (the canvas draws 316 with the bar).
    func testSplitViewMatchesClosed() {
        let on = layout(371.5, 581, compact: true, eval: true)
        XCTAssertEqual(on.mode, .stack)
        XCTAssertEqual(on.board, 316, accuracy: 1)
        XCTAssertEqual(layout(371.5, 581, compact: true, eval: false).board, 339)
        XCTAssertTrue(on.short)
    }

    // IL: 951 × 669, 867 wide inside the side bar (decision 11).
    func testOpenWideIsTwoPanesWithA504Board() {
        let on = layout(867, 581, compact: false, eval: true), off = layout(867, 581, compact: false, eval: false)
        XCTAssertEqual(on.mode, .panes); XCTAssertEqual(off.mode, .panes)
        XCTAssertEqual(on.board, 504); XCTAssertEqual(off.board, 504, "Hiding the bar gives its room to the column")
        XCTAssertEqual(on.boardFrame.minX, 40); XCTAssertEqual(on.column.minX, 568)
        XCTAssertEqual(on.column.width, 279); XCTAssertGreaterThanOrEqual(on.column.width - 16, 263)
        XCTAssertEqual(off.column.width, 299)
        XCTAssertFalse(on.short)
    }

    // IP: 669 × 951, nav bar 82 and bottom bar 48 + 34.
    func testOpenTallStacksAndKeepsTheColumn() {
        let on = layout(669, 787, compact: false, eval: true), off = layout(669, 787, compact: false, eval: false)
        XCTAssertEqual(on.mode, .stack)
        XCTAssertEqual(on.board, 512); XCTAssertEqual(off.board, 512)
        XCTAssertEqual(on.boardFrame.minX, 88.5, accuracy: 0.01)
        XCTAssertEqual(on.evalFrame?.minX ?? 0, 68.5, accuracy: 0.01)
        XCTAssertEqual(on.column.height, 247, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(on.column.height, BoardLayout.minColumnHeight)
        XCTAssertTrue(on.short)
    }

    // PP: 669 × 606 flat, 669 × 465 bent, with horizontal bars. Wider than tall, so two panes.
    func testPinnedVideoIsTwoPanes() {
        let flat = layout(669, 488, compact: false, eval: true), bent = layout(669, 347, compact: false, eval: true)
        XCTAssertEqual(flat.mode, .panes); XCTAssertEqual(bent.mode, .panes)
        XCTAssertEqual(flat.board, 304); XCTAssertEqual(bent.board, 304)
        XCTAssertGreaterThanOrEqual(flat.column.width, BoardLayout.minColumnWidth)
        XCTAssertLessThanOrEqual(bent.boardFrame.maxY, 347)
    }

    // iPad 11″: 834 × 1194 and 1194 × 834 with the nav and bottom bars (D11 checks these on the device).
    func testIPadFollowsTheSameRule() {
        let portrait = layout(834, 1050, compact: false, eval: true), landscape = layout(1194, 690, compact: false, eval: true)
        XCTAssertEqual(portrait.mode, .stack); XCTAssertEqual(portrait.board, 768)
        XCTAssertEqual(landscape.mode, .panes); XCTAssertEqual(landscape.board, 672, "Capped by the height")
        XCTAssertLessThanOrEqual(landscape.boardFrame.maxY + BoardLayout.inset, 690)
    }

    func testRegularBoardsSnapToEightPoints() {
        for size in [CGSize(width: 867, height: 581), CGSize(width: 669, height: 787), CGSize(width: 700, height: 500), CGSize(width: 1000, height: 1001)] {
            let board = BoardLayout(container: size, compact: false, evalBar: true).board
            XCTAssertEqual(board.truncatingRemainder(dividingBy: 8), 0, "\(size)")
        }
    }

    func testEverythingStaysInsideTheContainer() {
        for (size, compact) in [(CGSize(width: 382, height: 590), true), (CGSize(width: 867, height: 581), false),
                                (CGSize(width: 669, height: 787), false), (CGSize(width: 669, height: 347), false)] {
            for eval in [true, false] {
                let l = BoardLayout(container: size, compact: compact, evalBar: eval), bounds = CGRect(origin: .zero, size: size)
                XCTAssertTrue(bounds.contains(l.boardFrame), "\(size)"); XCTAssertTrue(bounds.contains(l.column), "\(size)")
                XCTAssertFalse(l.boardFrame.intersects(l.column), "\(size)")
                if let bar = l.evalFrame { XCTAssertTrue(bounds.contains(bar)); XCTAssertFalse(bar.intersects(l.boardFrame)) }
            }
        }
    }

    func testAnEmptyContainerGivesAnEmptyBoard() {
        XCTAssertEqual(BoardLayout(container: .zero, compact: true, evalBar: true).board, 0)
        XCTAssertEqual(BoardLayout(container: .zero, compact: false, evalBar: true).board, 0)
    }

    func testTheDivisionIsIgnoredUntilD07() {
        let division = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        XCTAssertEqual(BoardLayout(container: CGSize(width: 867, height: 581), compact: false, evalBar: true, division: division),
                       layout(867, 581, compact: false, eval: true))
    }
}
