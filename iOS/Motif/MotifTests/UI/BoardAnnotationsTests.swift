import XCTest
@testable import Motif

final class BoardAnnotationsTests: XCTestCase {
    func testSquareRectsFollowOrientation() {
        XCTAssertEqual(BoardOverlay.rect("a8", .white, 10), CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(BoardOverlay.rect("h1", .white, 10), CGRect(x: 70, y: 70, width: 10, height: 10))
        XCTAssertEqual(BoardOverlay.rect("h1", .black, 10), CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(BoardOverlay.rect("e4", .black, 10), CGRect(x: 30, y: 30, width: 10, height: 10))
        XCTAssertEqual(BoardOverlay.center("e4", .white, 10), CGPoint(x: 45, y: 45))
        for outside in ["i1", "a0", "a9", "", "e44", "E4"] { XCTAssertNil(BoardOverlay.rect(outside, .white, 10), outside) }
    }
    func testATapOnAnArrowsShaftFindsIt() {
        // Squares of 50 pt, White at the bottom: f3 is centred at (275, 275), g5 at (325, 175).
        let arrows = [BoardArrow(from: "f3", to: "g5", side: .own), BoardArrow(from: "a1", to: "a8", side: .theirs)]
        XCTAssertEqual(BoardOverlay.arrowHit(CGPoint(x: 300, y: 225), arrows: arrows, orientation: .white, size: 50), 0, "mid-shaft")
        XCTAssertEqual(BoardOverlay.arrowHit(CGPoint(x: 312, y: 225), arrows: arrows, orientation: .white, size: 50), 0, "within 12 pt")
        XCTAssertNil(BoardOverlay.arrowHit(CGPoint(x: 340, y: 225), arrows: arrows, orientation: .white, size: 50), "too far off")
        XCTAssertNil(BoardOverlay.arrowHit(CGPoint(x: 275, y: 275), arrows: arrows, orientation: .white, size: 50), "the piece it starts on")
        XCTAssertNil(BoardOverlay.arrowHit(CGPoint(x: 322, y: 180), arrows: arrows, orientation: .white, size: 50), "the square it ends on")
        XCTAssertEqual(BoardOverlay.arrowHit(CGPoint(x: 28, y: 200), arrows: arrows, orientation: .white, size: 50), 1)
        // Seen from Black the same arrow sits elsewhere.
        XCTAssertNil(BoardOverlay.arrowHit(CGPoint(x: 300, y: 225), arrows: arrows, orientation: .black, size: 50))
        XCTAssertEqual(BoardOverlay.arrowHit(CGPoint(x: 100, y: 175), arrows: arrows, orientation: .black, size: 50), 0)
        XCTAssertNil(BoardOverlay.arrowHit(CGPoint(x: 300, y: 225), arrows: [], orientation: .white, size: 50))
    }
    func testArrowShapes() {
        XCTAssertNil(BoardArrowShape(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5), size: 50))
        let shape = BoardArrowShape(from: CGPoint(x: 25, y: 25), to: CGPoint(x: 125, y: 25), size: 50)
        XCTAssertEqual(shape?.base, CGPoint(x: 104, y: 25)); XCTAssertEqual(shape?.width, 7.5)
        XCTAssertEqual(BoardArrow(from: "f3", to: "g5", side: .own).line, "f3g5")
    }
    func testEmptyUntilSomethingIsMarked() {
        var annotations = BoardAnnotations()
        XCTAssertTrue(annotations.isEmpty)
        annotations.dots.insert("g7")
        XCTAssertFalse(annotations.isEmpty)
    }
    func testVoiceOverNamesEveryMarkOnASquare() {
        let annotations = BoardAnnotations(
            tints: ["f7": .red, "e4": .quickScan, "e5": .orange], dots: ["g7"], rings: ["f7": .correct, "c6": .missed],
            ghost: BoardGhost(square: "g5", piece: Board.Piece(square: "g5", type: .knight, color: .white)))
        XCTAssertEqual(annotations.accessibilityDescription("f7"), "marked red, loses material, correct")
        XCTAssertEqual(annotations.accessibilityDescription("e4"), "marked")
        XCTAssertEqual(annotations.accessibilityDescription("e5"), "marked orange, attacked as often as defended")
        XCTAssertEqual(annotations.accessibilityDescription("g7"), "dot")
        XCTAssertEqual(annotations.accessibilityDescription("c6"), "missed")
        XCTAssertEqual(annotations.accessibilityDescription("g5"), "White Knight to play here")
        XCTAssertNil(annotations.accessibilityDescription("a1"))
    }
    func testEveryMarkColourIsInTheAssetCatalog() {
        for name in ["BoardMarkHighlight", "BoardMarkRed", "BoardMarkOrange", "BoardMarkDot", "BoardRingCorrect",
                     "BoardRingMissed", "BoardRingExtra", "BoardArrowOwn", "BoardArrowTheirs"] {
            guard let color = UIColor(named: name, in: Bundle(for: AppState.self), compatibleWith: nil) else { XCTFail(name); continue }
            let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            let high = color.resolvedColor(with: UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .light), .init(accessibilityContrast: .high)]))
            XCTAssertNotEqual(light, dark, name); XCTAssertNotEqual(light, high, name)
        }
    }
}
