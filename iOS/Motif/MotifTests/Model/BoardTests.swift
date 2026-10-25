import XCTest
@testable import Motif

/// One test for each of the 11 cases in src/model/board.test.ts.
final class BoardTests: XCTestCase {
    private let mate = "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"
    private let promotion = "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"

    func testEnumerates64SquaresStartingAtA1() {
        XCTAssertEqual(Board.squares.count, 64)
        XCTAssertEqual(Board.squares.first, "a1")
        XCTAssertEqual(Board.squares.last, "h8")
    }

    func testReportsTheSideToMove() {
        XCTAssertEqual(Board.turnOf(mate), .white)
        XCTAssertEqual(Board.turnOf("6k1/5ppp/8/8/8/8/8/R5K1 b - - 0 1"), .black)
    }

    func testListsTargetsForAPiece() {
        let targets = Board.targetsFrom(mate, "a1")
        XCTAssertNotNil(targets["a8"])
        XCTAssertNotNil(targets["b1"])
        XCTAssertNil(targets["b2"], "Rooks do not move diagonally")
    }

    func testReturnsNothingForEmptyOrMalformedSquare() {
        XCTAssertTrue(Board.targetsFrom(mate, "d4").isEmpty)
        XCTAssertTrue(Board.targetsFrom(mate, "zz").isEmpty)
    }

    func testCollapsesFourPromotionMovesIntoOneTarget() {
        XCTAssertEqual(Board.targetsFrom(promotion, "a7")["a8"], .init(promotion: true, capture: false))
        XCTAssertTrue(Board.needsPromotion(promotion, "a7", "a8"))
    }

    func testFlagsCapturesForTheBoardUI() {
        let fen = "4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1"
        let targets = Board.targetsFrom(fen, "e4")
        XCTAssertEqual(targets["d5"]?.capture, true)
        XCTAssertEqual(targets["e5"]?.capture, false)
    }

    func testDoesNotOfferMovesThatLeaveKingInCheck() {
        let pinned = "4k3/8/8/8/8/4q3/4R3/4K3 w - - 0 1"
        let targets = Board.targetsFrom(pinned, "e2")
        XCTAssertNil(targets["a2"], "Stepping off the file exposes the king")
        XCTAssertNotNil(targets["e3"], "Capturing the pinner is fine")
    }

    func testReturnsTheResultingPosition() throws {
        let after = try XCTUnwrap(Board.applyUci(mate, uci("a1a8")))
        XCTAssertTrue(after.contains("R5k1"))
        XCTAssertTrue(after.contains(" b "))
    }

    func testReturnsNilForAnIllegalMove() throws {
        XCTAssertNil(Board.applyUci(mate, try uci("a1b2")))
        XCTAssertNil(Board.applyUci(mate, try uci("d4d5")), "No piece there")
        XCTAssertFalse(Board.isLegal(mate, try uci("a1b2")))
    }

    func testHonoursThePromotionPiece() throws {
        XCTAssertTrue(try XCTUnwrap(Board.applyUci(promotion, uci("a7a8q"))).contains("Q3k3"))
        XCTAssertTrue(try XCTUnwrap(Board.applyUci(promotion, uci("a7a8n"))).contains("N3k3"))
    }

    func testRendersSANForDisplay() throws {
        XCTAssertEqual(Board.sanFor(mate, try uci("a1a8")), "Ra8#")
        XCTAssertEqual(Board.sanFor(promotion, try uci("a7a8n")), "a8=N")
        XCTAssertEqual(Board.sanFor(promotion, try uci("a7a8q")), "a8=Q+")
        XCTAssertNil(Board.sanFor(mate, try uci("a1b2")))
    }
}
