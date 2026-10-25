import XCTest
@testable import Motif

final class BoardInteractionTests: XCTestCase {
    let fen = "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"
    func testTapAndDragShareTheSameLegalMovePath() throws {
        var taps = BoardInteraction(fen: fen), drag = taps
        XCTAssertNil(taps.tap("a1")); XCTAssertEqual(taps.selected, "a1")
        XCTAssertEqual(taps.tap("a8"), .move(try uci("a1a8")))
        XCTAssertEqual(drag.drop("a1", "a8"), .move(try uci("a1a8")))
        XCTAssertNil(taps.selected)
    }
    func testLegalWrongSquareStillEmitsSoTheRunnerCanJudge() throws {
        var board = BoardInteraction(fen: fen)
        _ = board.tap("a1"); XCTAssertEqual(board.tap("a2"), .move(try uci("a1a2")))
    }
    func testIllegalDropOffBoardAndDeselectProduceNothing() {
        var board = BoardInteraction(fen: fen)
        XCTAssertNil(board.drop("a1", nil)); XCTAssertNil(board.drop("a1", "d4"))
        _ = board.tap("a1"); XCTAssertNil(board.tap("a1")); XCTAssertNil(board.selected)
        _ = board.tap("a1"); XCTAssertNil(board.tap("d4")); XCTAssertNil(board.selected)
        XCTAssertNil(board.tap("outside"))
    }
    func testTappingAnOwnPieceReselects() {
        var board = BoardInteraction(fen: Board.defaultPosition)
        _ = board.tap("b1"); XCTAssertNil(board.tap("g1")); XCTAssertEqual(board.selected, "g1")
        XCTAssertEqual(Set(board.targets.keys), ["f3", "h3"])
    }
    func testPromotionHasOneTargetFourChoicesAndExactlyOneOutput() throws {
        let position = "7k/4P3/8/8/8/8/8/6K1 w - - 0 1"
        for piece in [PieceType.queen, .rook, .bishop, .knight] {
            var board = BoardInteraction(fen: position)
            _ = board.tap("e7"); XCTAssertEqual(board.targets.count, 1)
            XCTAssertNil(board.tap("e8")); XCTAssertEqual(board.pending, .promotion("e7", "e8"))
            XCTAssertEqual(board.choices, [.queen, .rook, .bishop, .knight])
            XCTAssertNil(board.choose(.pawn)); XCTAssertNotNil(board.pending)
            XCTAssertEqual(board.choose(piece), .move(try uci("e7e8" + piece.rawValue)))
            XCTAssertNil(board.choose(piece))
        }
    }
    func testCancelledPromotionAndPlacementCostNothing() {
        var promotion = BoardInteraction(fen: "7k/4P3/8/8/8/8/8/6K1 w - - 0 1")
        XCTAssertNil(promotion.drop("e7", "e8")); promotion.cancel(); XCTAssertNil(promotion.choose(.queen))
        var placement = BoardInteraction(fen: fen, placing: .white)
        XCTAssertNil(placement.tap("g6")); placement.cancel(); XCTAssertNil(placement.choose(.knight))
    }
    func testPlacementCannotDragOrReplaceAPieceAndDoesNotOfferAKing() {
        var board = BoardInteraction(fen: fen, placing: .white)
        XCTAssertNil(board.drop("a1", "a8")); XCTAssertNil(board.tap("a1")); XCTAssertNil(board.pending)
        XCTAssertNil(board.tap("g6")); XCTAssertEqual(board.pending, .placement("g6"))
        XCTAssertEqual(board.choices, [.queen, .rook, .bishop, .knight, .pawn])
        XCTAssertNil(board.choose(.king))
        XCTAssertEqual(board.choose(.knight), .placement(Placement(color: .white, type: .knight, square: "g6")))
        XCTAssertNil(board.choose(.knight))
    }
    func testNewFenAndDisabledBoardAbandonInFlightInteraction() {
        var board = BoardInteraction(fen: fen)
        _ = board.tap("a1"); board.reset(Board.defaultPosition); XCTAssertNil(board.selected); XCTAssertNil(board.pending)
        board.interactive = false
        XCTAssertNil(board.tap("e2")); XCTAssertNil(board.drop("e2", "e4"))
    }
    func testCaptureAndQuietTargetsHaveDistinctMetadata() {
        var board = BoardInteraction(fen: "6k1/5ppp/8/8/8/8/r7/R5K1 w - - 0 1")
        _ = board.tap("a1")
        XCTAssertEqual(board.targets["a2"]?.capture, true); XCTAssertEqual(board.targets["b1"]?.capture, false)
    }
}
