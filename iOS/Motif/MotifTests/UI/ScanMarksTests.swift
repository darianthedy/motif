import XCTest
@testable import Motif

/// Scan plan S07: what one tap, one drag or one arrow does to the step's marks.
final class ScanMarksTests: XCTestCase {
    /// Playtest 3: red first, as the scan looks for red first; an empty square away from the kings
    /// can only be a dot, so its first tap is one.
    func testAPieceGoesRedOrangeClearAKingZoneSquareRedOrangeDotClearAndAnyOtherEmptySquareDotClear() {
        var marks = ScanMarks()
        marks.cycleTarget("e4", on: .piece); XCTAssertEqual(marks.red, ["e4"])
        marks.cycleTarget("e4", on: .piece); XCTAssertEqual(marks.orange, ["e4"]); XCTAssertEqual(marks.red, [])
        marks.cycleTarget("e4", on: .piece); XCTAssertEqual(marks.targets, [:])
        marks.cycleTarget("g7", on: .kingZone); XCTAssertEqual(marks.red, ["g7"])
        marks.cycleTarget("g7", on: .kingZone); XCTAssertEqual(marks.orange, ["g7"])
        marks.cycleTarget("g7", on: .kingZone); XCTAssertEqual(marks.dots, ["g7"]); XCTAssertEqual(marks.orange, [])
        marks.cycleTarget("g7", on: .kingZone); XCTAssertEqual(marks.targets, [:])
        marks.cycleTarget("d5", on: .empty); XCTAssertEqual(marks.dots, ["d5"])
        marks.cycleTarget("d5", on: .empty); XCTAssertEqual(marks.targets, [:])
    }
    /// Playtest 2: a carried quick-scan mark drops its fill (dimmed violet read as pink, like red),
    /// keeping only its notch; carried targets keep a dimmed fill.
    func testACarriedQuickScanMarkHasNoFill() {
        XCTAssertNotNil(SquareMark.quickScan.fill(faded: false))
        XCTAssertNil(SquareMark.quickScan.fill(faded: true))
        XCTAssertNotNil(SquareMark.red.fill(faded: true))
        XCTAssertNil(SquareMark.orange.fill(faded: true))
    }
    func testTargetsDrawAsTintsAndDots() {
        let marks = ScanMarks(targets: ["f7": .red, "e5": .orange, "g7": .dot])
        XCTAssertEqual(marks.annotations.tints, ["f7": .red, "e5": .orange]); XCTAssertEqual(marks.annotations.dots, ["g7"])
    }
    func testDrawingAnArrowTwiceTakesItAway() {
        var marks = ScanMarks()
        marks.drawArrow(from: "f3", to: "g5", side: .own)
        marks.drawArrow(from: "f6", to: "e4", side: .theirs)
        marks.drawArrow(from: "f3", to: "f3", side: .own)
        XCTAssertEqual(marks.arrows.map(\.line), ["f3g5", "f6e4"]); XCTAssertEqual(marks.lines, ["f3g5", "f6e4"])
        marks.drawArrow(from: "f3", to: "g5", side: .own)
        XCTAssertEqual(marks.arrows, [BoardArrow(from: "f6", to: "e4", side: .theirs)])
        marks.removeArrow(at: 3); marks.removeArrow(at: 0)
        XCTAssertEqual(marks.arrows, [])
    }
    func testArrowLabelsReadAsMoves() {
        let fen = "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
        XCTAssertEqual(ScanArrowList.text(BoardArrow(from: "f6", to: "e4", side: .theirs), fen: fen), "Nxe4")
        XCTAssertEqual(ScanArrowList.text(BoardArrow(from: "c4", to: "f7", side: .own), fen: fen), "Bxf7+")
        XCTAssertEqual(ScanArrowList.text(BoardArrow(from: "f3", to: "g5", side: .own), fen: fen), "Ng5")
        // Playtest 3: one notation. Not a move (the d2 pawn is in the way), still SAN, as on the card.
        XCTAssertEqual(ScanArrowList.text(BoardArrow(from: "d1", to: "d5", side: .own), fen: fen), "Qd5")
        XCTAssertEqual(ScanImport.arrowSans(fen, from: "f2", to: "g5"), [], "no pawn move: the arrow step refuses it")
    }
}
