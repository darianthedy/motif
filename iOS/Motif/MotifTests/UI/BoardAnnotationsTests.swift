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
