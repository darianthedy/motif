import XCTest
@testable import Motif

final class PuzzleGameTests: XCTestCase {
    func testStartsAtThePuzzlePositionWithTheFirstSolutionAsTheMainLine() {
        let fen = "r2r2k1/1p3ppp/p3b3/8/1n6/8/PP1Q1PPP/3R2K1 w - - 0 1"
        let game = puzzleGame(testPuzzle([["d2d8", "a8d8", "d1d8"], ["d2e2"]], fen: fen), event: "Back rank")
        XCTAssertEqual(game.startFen, fen)
        XCTAssertEqual(game.headers["FEN"], fen)
        XCTAssertEqual(game.headers["Event"], "Back rank")
        XCTAssertEqual(lineTo(game, [0, 0, 0]).map(\.san), ["Qxd8+", "Rxd8", "Rxd8#"])
        XCTAssertEqual(game.moves.map(\.san), ["Qxd8+", "Qe2"])
    }
    func testAPositionWithoutMoveCountersStillReadsBackAsAGame() throws {
        let game = puzzleGame(testPuzzle([["a1a8"]], fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - -"))
        XCTAssertEqual(game.startFen, "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
        let read = try parsePgn(writePgn(game))
        XCTAssertEqual(read.startFen, game.startFen); XCTAssertEqual(read.moves.map(\.san), ["Ra8#"])
    }
    func testSolutionsSharingAFirstMoveBranchLater() {
        let game = puzzleGame(testPuzzle([["a1a8"], ["a1a8"]]))
        XCTAssertEqual(game.moves.count, 1)
        XCTAssertEqual(game.headers["Event"], "Puzzle")
    }
    func testMissingPiecePuzzleOpensWithTheAnswerPlaced() {
        let game = puzzleGame(testPuzzle(fen: missingPieceFEN, addPiece: missingKnight))
        XCTAssertEqual(game.startFen, Board.withPiece(missingPieceFEN, missingKnight))
        XCTAssertTrue(game.moves.isEmpty)
        XCTAssertNoThrow(try parsePgn(writePgn(game)))
    }
}
