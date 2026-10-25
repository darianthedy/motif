import XCTest
@testable import Motif

/// One case for every edit.test.ts case.
final class EditTests: XCTestCase {
    private func game() throws -> ParsedGame { try parsePgn("1. e4 e5 (1... c5 2. Nf3) 2. Nf3 *") }
    func testFollowsAPathIntoAVariation() throws {
        let game = try game()
        XCTAssertEqual(lineTo(game, [0, 1, 0]).map(\.san), ["e4", "c5", "Nf3"])
        XCTAssertNil(nodeAt(game, []))
        XCTAssertEqual(fenAt(game, []), game.startFen)
        XCTAssertEqual(fenAt(game, [0]), game.moves[0].fen)
    }
    func testTellsAPathThatLeadsNowhere() throws {
        XCTAssertTrue(validPath(try game(), [0, 1, 0]))
        XCTAssertFalse(validPath(try game(), [0, 2]))
    }
    func testStepsForwardAlongTheMainLineToItsEnd() throws {
        let game = try game()
        XCTAssertEqual(forward(game, []), [0])
        XCTAssertEqual(forward(game, [0, 1]), [0, 1, 0])
        XCTAssertNil(forward(game, [0, 0, 0]))
    }
    func testKnowsTheMainLine() {
        XCTAssertTrue(onMainLine([0, 0, 0])); XCTAssertFalse(onMainLine([0, 1, 0]))
    }
    func testCarriesTheLineOnAtItsEnd() throws {
        let start = newGame()
        let first = try playMove(start, [], testMove("e2e4"))
        let second = try playMove(first.game, first.path, testMove("e7e5"))
        XCTAssertEqual(second.path, [0, 0])
        XCTAssertEqual(lineTo(second.game, second.path).map(\.san), ["e4", "e5"])
        XCTAssertEqual(start.moves, [])
    }
    func testStartsAVariationInTheMiddleOfOne() throws {
        let result = try playMove(parsePgn("1. e4 e5 2. Nf3 *"), [0], testMove("c7c5"))
        XCTAssertEqual(result.path, [0, 1])
        XCTAssertTrue(writePgn(result.game).contains("1. e4 e5 (1... c5) 2. Nf3 *"))
    }
    func testGoesToAnExistingMoveWithoutAddingItTwice() throws {
        let game = try parsePgn("1. e4 e5 (1... c5) *")
        let result = try playMove(game, [0], testMove("c7c5"))
        XCTAssertEqual(result.path, [0, 1]); XCTAssertEqual(result.game, game)
    }
    func testRefusesAnIllegalMove() {
        XCTAssertThrowsError(try playMove(newGame(), [], testMove("e2e5"))) {
            XCTAssertTrue(String(describing: $0).contains("not a legal move"))
        }
    }
    func testDeletesAMoveAndWhatFollowsIt() throws {
        let result = deleteFrom(try game(), [0, 1])
        XCTAssertEqual(result.path, [0])
        XCTAssertTrue(writePgn(result.game).contains("1. e4 e5 2. Nf3 *"))
    }
    func testPromotesAVariationWhereItBranchesOff() throws {
        let game = try parsePgn("1. e4 e5 (1... c5 2. Nf3 d6) 2. Nf3 *")
        let result = promoteVariation(game, [0, 1, 0, 0])
        XCTAssertEqual(result.path, [0, 0, 0, 0])
        XCTAssertTrue(writePgn(result.game).contains("1. e4 c5 (1... e5 2. Nf3) 2. Nf3 d6 *"))
    }
    func testLeavesTheMainLineAsItIs() throws {
        let game = try parsePgn("1. e4 e5 *")
        XCTAssertEqual(promoteVariation(game, [0, 0]).game, game)
    }
    func testSetsAndClearsMoveAndGameComments() throws {
        var game = try parsePgn("1. e4 *")
        game = setComment(game, [0], "  best by test} ")
        XCTAssertEqual(game.moves[0].comment, "best by test")
        game = setComment(game, [], "A note")
        XCTAssertEqual(game.comment, "A note")
        game = setComment(game, [0], " ")
        XCTAssertNil(game.moves[0].comment)
        XCTAssertEqual(try parsePgn(writePgn(game)), game)
    }
    func testSetsAndRemovesHeadersButNeverTheStartingPosition() {
        let fen = "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"
        let game = setHeaders(newGame(fen), PgnHeaders([
            ("White", " Me "), ("Event", ""), ("FEN", "nonsense"), ("Result", ""),
        ]))
        XCTAssertEqual(game.headers["White"], "Me"); XCTAssertNil(game.headers["Event"])
        XCTAssertEqual(game.headers["FEN"], fen); XCTAssertEqual(game.headers["Result"], "*")
    }
}
