import XCTest
@testable import Motif

/// One case for every table.test.ts case.
final class TableTests: XCTestCase {
    func testPutsBothSidesOfAMoveOnOneRow() throws {
        XCTAssertEqual(testShowTable(moveTable(try parsePgn("1. e4 e5 2. Nf3 *"))), ["1. e4 e5", "2. Nf3 …"])
    }
    func testPutsAlternativesToBlackAfterTheRow() throws {
        let items = moveTable(try parsePgn("1. e4 e5 (1... c5 2. Nf3) (1... e6) 2. Nf3 *"))
        XCTAssertEqual(testShowTable(items), ["1. e4 e5", "( c5 | e6 )", "2. Nf3 …"])
        guard case .variations(let fen, let alternatives) = items[1],
              case .row(_, let white, _) = items[0] else { return XCTFail("Wrong table structure") }
        XCTAssertEqual(alternatives.map(\.path), [[0, 1], [0, 2]])
        XCTAssertEqual(fen, white?.node.fen)
    }
    func testBreaksTheRowAtAnAlternativeToWhite() throws {
        let items = moveTable(try parsePgn("1. e4 (1. d4 d5) 1... e5 2. Nf3 *"))
        XCTAssertEqual(testShowTable(items), ["1. e4 …", "( d4 )", "1. … e5", "2. Nf3 …"])
        guard case .row(_, _, let black) = items[2] else { return XCTFail("Wrong row") }
        XCTAssertEqual(black?.path, [0, 0])
    }
    func testStartsWithAGapWhenBlackMovesFirst() throws {
        let game = try parsePgn("[SetUp \"1\"]\n[FEN \"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1\"]\n\n1... e5 2. Nf3 *")
        XCTAssertEqual(testShowTable(moveTable(game)), ["1. … e5", "2. Nf3 …"])
    }
    func testIsEmptyForAGameWithNoMoves() throws {
        XCTAssertEqual(moveTable(try parsePgn("*")), [])
    }
    func testCountsALineAlongItsOwnMainLine() throws {
        let game = try parsePgn("1. e4 e5 (1... c5 2. Nf3 d6) 2. Nf3 Nc6 *")
        XCTAssertEqual(lineLength(game.moves[0]), 4)
        XCTAssertEqual(lineLength(game.moves[0].children[1]), 3)
    }
    func testCountsEveryMoveAfterOneIncludingVariations() throws {
        XCTAssertEqual(movesFrom(try parsePgn("1. e4 e5 (1... c5 2. Nf3 d6) 2. Nf3 Nc6 *").moves[0]), 7)
    }
    func testTellsAPathInsideAnother() {
        XCTAssertTrue(startsWith([0, 1, 0], [0, 1]))
        XCTAssertTrue(startsWith([0, 1], [0, 1]))
        XCTAssertFalse(startsWith([0, 0, 0], [0, 1]))
        XCTAssertFalse(startsWith([0], [0, 1]))
    }
}
