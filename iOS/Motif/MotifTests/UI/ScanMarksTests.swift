import XCTest
@testable import Motif

/// Scan plan S07: what one tap, one drag or one arrow does to the step's marks.
final class ScanMarksTests: XCTestCase {
    func testAPieceGoesRedOrangeClearAndAnEmptySquareTakesADot() {
        var marks = ScanMarks()
        marks.cycleTarget("e4", piece: true); XCTAssertEqual(marks.red, ["e4"])
        marks.cycleTarget("e4", piece: true); XCTAssertEqual(marks.orange, ["e4"]); XCTAssertEqual(marks.red, [])
        marks.cycleTarget("e4", piece: true); XCTAssertEqual(marks.targets, [:])
        marks.cycleTarget("g7", piece: false); XCTAssertEqual(marks.dots, ["g7"])
        marks.cycleTarget("g7", piece: false); XCTAssertEqual(marks.dots, [])
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
}
