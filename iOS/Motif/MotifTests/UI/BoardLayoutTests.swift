import XCTest
import SwiftUI
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

    // D07: the fold division (§6.16). Frames are in the container's coordinates, margins included.
    private func folded(_ width: CGFloat, _ height: CGFloat, compact: Bool = false, eval: Bool, _ division: CGRect) -> BoardLayout {
        BoardLayout(container: CGSize(width: width, height: height), compact: compact, evalBar: eval, division: division)
    }
    /// FB: IL bent, the division 455.5–495.5 runs top to bottom (it starts above the container, under the title).
    private let book = CGRect(x: 455.5, y: -54, width: 40, height: 669)
    /// FT: IP bent, the division at y 373.5 in the window, 291.5 under the 82 pt navigation bar.
    private let tabletop = CGRect(x: 0, y: 291.5, width: 669, height: 40)

    func testBookPutsTheBoardOnTheLeadingPage() {
        let on = folded(867, 581, eval: true, book), off = folded(867, 581, eval: false, book)
        XCTAssertEqual(on.mode, .pages); XCTAssertEqual(off.mode, .pages); XCTAssertTrue(on.sideBySide)
        XCTAssertEqual(on.board, 392, "Analysis with the eval bar"); XCTAssertEqual(off.board, 416, "Sessions and puzzle detail")
        XCTAssertEqual(on.boardFrame.minX, 40); XCTAssertEqual(off.boardFrame.minX, 20)
        XCTAssertLessThanOrEqual(on.boardFrame.maxX, 455.5); XCTAssertLessThanOrEqual(off.boardFrame.maxX, 455.5)
        XCTAssertEqual(on.column.minX, 499.5); XCTAssertEqual(on.column.width, 351.5)
        XCTAssertEqual(off.column, on.column, "The column is the trailing page either way")
        XCTAssertFalse(on.short)
    }

    func testTabletopPutsTheBoardAboveTheDivision() {
        let on = folded(669, 787, eval: true, tabletop), off = folded(669, 787, eval: false, tabletop)
        XCTAssertEqual(on.mode, .halves); XCTAssertEqual(off.mode, .halves); XCTAssertFalse(on.sideBySide)
        XCTAssertEqual(on.board, 272, "Decision 10"); XCTAssertEqual(off.board, 272)
        XCTAssertLessThanOrEqual(on.boardFrame.maxY, 291.5)
        XCTAssertEqual(on.boardFrame.midX - (BoardLayout.evalBarWidth + on.evalGap) / 2, 669 / 2, accuracy: 0.01, "Centred with its bar, as on IP")
        XCTAssertEqual(on.column.minY, 339.5); XCTAssertEqual(on.column.height, 439.5, accuracy: 0.01)
        XCTAssertEqual(on.column.minX, 20); XCTAssertEqual(on.column.width, 629)
    }

    // SV: 469 × 669 with the side bar on the outer edge leaves 385 pt; the 13.5 pt strip on the
    // inner edge is an inset (F33), so each side lays out as the 371.5 pt container.
    func testSplitViewInnerStripIsAnInset() {
        let left = folded(385, 581, compact: true, eval: true, CGRect(x: 371.5, y: -54, width: 13.5, height: 669))
        let right = folded(385, 581, compact: true, eval: true, CGRect(x: 0, y: -54, width: 13.5, height: 669))
        let plain = layout(371.5, 581, compact: true, eval: true)
        for side in [left, right] {
            XCTAssertEqual(side.mode, .stack); XCTAssertEqual(side.board, plain.board); XCTAssertEqual(side.board, 316, accuracy: 1)
            XCTAssertTrue(side.short)
        }
        XCTAssertEqual(left.boardFrame, plain.boardFrame); XCTAssertEqual(left.column, plain.column)
        XCTAssertLessThanOrEqual(left.column.maxX, 371.5); XCTAssertEqual(left.padding.trailing, 29.5)
        XCTAssertEqual(right.boardFrame, plain.boardFrame.offsetBy(dx: 13.5, dy: 0))
        XCTAssertEqual(right.column, plain.column.offsetBy(dx: 13.5, dy: 0))
        XCTAssertEqual(right.padding.leading, 29.5); XCTAssertEqual(right.padding.trailing, 16)
    }

    // Pinned video bent: a 9.8 pt strip at the top edge is an inset, not a fold.
    func testAStripAtTheTopIsAnInset() {
        let bent = folded(669, 347, eval: true, CGRect(x: 0, y: 0, width: 669, height: 9.8))
        XCTAssertEqual(bent.mode, .panes)
        XCTAssertGreaterThanOrEqual(bent.boardFrame.minY, 9.8 + BoardLayout.inset)
        XCTAssertLessThanOrEqual(bent.boardFrame.maxY, 347)
        XCTAssertEqual(bent.padding.top, 9.8 + BoardLayout.inset, accuracy: 0.01)
    }

    // CI's IL is flat: the division is inactive, `motifDivision` gives nil, and the layout is D05's.
    func testOpenFlatIsUnchanged() {
        for eval in [true, false] {
            let flat = BoardLayout(container: CGSize(width: 867, height: 581), compact: false, evalBar: eval, division: nil)
            XCTAssertEqual(flat, layout(867, 581, compact: false, eval: eval))
            XCTAssertEqual(flat.mode, .panes); XCTAssertEqual(flat.board, 504)
            XCTAssertEqual(flat.spacing, BoardLayout.paneGap)
            XCTAssertEqual(flat.padding, EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        }
    }

    func testNothingCrossesTheDivision() {
        let cases: [(CGSize, Bool, CGRect)] = [
            (CGSize(width: 867, height: 581), false, book), (CGSize(width: 669, height: 787), false, tabletop),
            (CGSize(width: 385, height: 581), true, CGRect(x: 371.5, y: -54, width: 13.5, height: 669)),
            (CGSize(width: 385, height: 581), true, CGRect(x: 0, y: -54, width: 13.5, height: 669)),
        ]
        for (size, compact, division) in cases {
            for eval in [true, false] {
                let l = BoardLayout(container: size, compact: compact, evalBar: eval, division: division)
                let bounds = CGRect(origin: .zero, size: size), d = division.intersection(bounds)
                XCTAssertFalse(l.boardFrame.intersects(d), "\(size) \(division)")
                XCTAssertFalse(l.column.intersects(d), "\(size) \(division)")
                if let bar = l.evalFrame { XCTAssertFalse(bar.intersects(d)) }
                XCTAssertTrue(bounds.contains(l.boardFrame)); XCTAssertTrue(bounds.contains(l.column))
                if !compact { XCTAssertEqual(l.board.truncatingRemainder(dividingBy: 8), 0) }
            }
        }
    }

    /// The views build the stack from `padding` and `spacing`; they must land the column on its frame.
    func testPaddingAndSpacingReproduceTheFrames() {
        let cases: [(CGSize, Bool, CGRect?)] = [
            (CGSize(width: 382, height: 590), true, nil), (CGSize(width: 867, height: 581), false, nil),
            (CGSize(width: 669, height: 787), false, nil), (CGSize(width: 867, height: 581), false, book),
            (CGSize(width: 669, height: 787), false, tabletop),
            (CGSize(width: 385, height: 581), true, CGRect(x: 0, y: -54, width: 13.5, height: 669)),
        ]
        for (size, compact, division) in cases {
            for eval in [true, false] {
                let l = BoardLayout(container: size, compact: compact, evalBar: eval, division: division)
                let pane = l.evalFrame.map { $0.union(l.boardFrame) } ?? l.boardFrame
                XCTAssertEqual(l.padding.top, pane.minY, accuracy: 0.01, "\(size)")
                if l.sideBySide {
                    XCTAssertEqual(l.padding.leading, pane.minX, accuracy: 0.01, "\(size)")
                    XCTAssertEqual(pane.maxX + l.spacing, l.column.minX, accuracy: 0.01, "\(size)")
                    XCTAssertEqual(size.width - l.padding.trailing, l.column.maxX, accuracy: 0.01, "\(size)")
                } else {
                    XCTAssertEqual(pane.maxY + l.spacing, l.column.minY, accuracy: 0.01, "\(size)")
                    XCTAssertEqual(l.padding.leading, l.column.minX, accuracy: 0.01, "\(size)")
                    XCTAssertEqual(size.width - l.padding.trailing, l.column.maxX, accuracy: 0.01, "\(size)")
                }
            }
        }
    }
}
