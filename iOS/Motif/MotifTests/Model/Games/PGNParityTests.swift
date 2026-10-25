import XCTest
@testable import Motif

/// Expected trees, PGN bytes, errors and model outputs come from the real TS
/// model. Header order is explicit in fixtures because JSON objects do not
/// preserve that order through Swift's keyed decoder.
final class PGNParityTests: XCTestCase {
    private struct Fixture: Decodable {
        struct TableCell: Decodable, Equatable {
            let path: MovePath
            let san: String
        }
        struct TableRow: Decodable {
            let kind: String
            let number: Double?
            let white: TableCell?
            let black: TableCell?
            let fen: String?
            let alternatives: [TableCell]?
        }
        struct Case: Decodable {
            let name: String
            let input: String
            let parsed: PgnFile
            let headerNames: [[String]]
            let written: [String]
            let reread: [PgnFile]
            let headers: PgnHeaders
            let tables: [[TableRow]]
        }
        struct Edit: Decodable {
            struct Step: Decodable {
                struct Operation: Decodable {
                    let kind: String
                    let path: MovePath?
                    let move: Uci?
                    let text: String?
                    let changes: [String: String]?
                    let changeNames: [String]?
                }
                let operation: Operation
                let game: ParsedGame
                let path: MovePath?
                let error: String?
                let written: String
                let headerNames: [String]
            }
            let name: String
            let input: String
            let steps: [Step]
        }
        struct Summary: Decodable {
            struct Query: Decodable { let query: String; let matches: Bool }
            let headers: PgnHeaders
            let title: String
            let subtitle: String
            let queries: [Query]
        }
        struct Comment: Decodable { let comment: String?; let displayed: String }
        struct LibraryCase: Decodable {
            struct Shift: Decodable { let id: String; let up: [GamePlacement]; let down: [GamePlacement] }
            let input: Library
            let collections: [GameCollection]
            let games: [Game]
            let moved: [GamePlacement]
            let shifts: [Shift]
        }
        let version: Int
        let cases: [Case]
        let edits: [Edit]
        let summaries: [Summary]
        let comments: [Comment]
        let library: LibraryCase
    }
    private func fixture() throws -> Fixture { try loadPuzzleFixture("pgn-roundtrip", as: Fixture.self) }

    func testParsedTreesErrorsAndWrittenBytesMatchTheWeb() throws {
        let fixture = try fixture()
        XCTAssertEqual(fixture.version, 1)
        for item in fixture.cases {
            let file = parsePgnFile(item.input)
            XCTAssertEqual(file, item.parsed, item.name)
            XCTAssertEqual(file.games.map(\.headers.names), item.headerNames, item.name)
            let written = file.games.map(writePgn)
            XCTAssertEqual(written.map { Array($0.utf8) }, item.written.map { Array($0.utf8) }, item.name)
            XCTAssertEqual(written.map(parsePgnFile), item.reread, item.name)
            for text in written {
                XCTAssertEqual(Array(writePgn(try parsePgn(text)).utf8), Array(text.utf8), item.name)
            }
        }
    }
    func testHeaderOnlyReadsMatchTheWeb() throws {
        for item in try fixture().cases {
            XCTAssertEqual(readHeaders(item.input), item.headers, item.name)
        }
    }
    func testMoveTablePathsAndRowsMatchTheWeb() throws {
        func cell(_ cell: Cell?) -> Fixture.TableCell? {
            cell.map { Fixture.TableCell(path: $0.path, san: $0.node.san) }
        }
        for item in try fixture().cases {
            let file = parsePgnFile(item.input)
            XCTAssertEqual(file.games.count, item.tables.count, item.name)
            guard file.games.count == item.tables.count else { continue }
            for (game, expected) in zip(file.games, item.tables) {
                let actual = moveTable(game)
                XCTAssertEqual(actual.count, expected.count, item.name)
                for (actual, expected) in zip(actual, expected) {
                    switch actual {
                    case .row(let number, let white, let black):
                        XCTAssertEqual(expected.kind, "row", item.name)
                        if let expectedNumber = expected.number { XCTAssertEqual(number, expectedNumber, item.name) }
                        else { XCTAssertTrue(number.isNaN, item.name) }
                        XCTAssertEqual(cell(white), expected.white, item.name)
                        XCTAssertEqual(cell(black), expected.black, item.name)
                    case .variations(let fen, let alternatives):
                        XCTAssertEqual(expected.kind, "variations", item.name)
                        XCTAssertEqual(fen, expected.fen, item.name)
                        XCTAssertEqual(alternatives.compactMap { cell($0) }, expected.alternatives, item.name)
                    }
                }
            }
        }
    }
    func testEditTracesMatchTheWebAndPreserveTheirInput() throws {
        for item in try fixture().edits {
            var game = try parsePgn(item.input)
            for step in item.steps {
                let original = game
                let originalText = writePgn(original)
                var path: MovePath?
                var error: String?
                let operation = step.operation
                do {
                    switch operation.kind {
                    case "play":
                        let result = try playMove(game, XCTUnwrap(operation.path), XCTUnwrap(operation.move))
                        game = result.game; path = result.path
                    case "delete":
                        let result = deleteFrom(game, try XCTUnwrap(operation.path))
                        game = result.game; path = result.path
                    case "promote":
                        let result = promoteVariation(game, try XCTUnwrap(operation.path))
                        game = result.game; path = result.path
                    case "comment":
                        game = setComment(game, try XCTUnwrap(operation.path), try XCTUnwrap(operation.text))
                    case "headers":
                        let names = try XCTUnwrap(operation.changeNames)
                        let values = try XCTUnwrap(operation.changes)
                        game = setHeaders(game, PgnHeaders(names.map { ($0, values[$0]!) }))
                    default: XCTFail("Unknown fixture operation \(operation.kind)")
                    }
                } catch let failure { error = String(describing: failure) }
                XCTAssertEqual(writePgn(original), originalText, item.name)
                XCTAssertEqual(error, step.error, item.name)
                XCTAssertEqual(path, step.path, item.name)
                XCTAssertEqual(game, step.game, item.name)
                XCTAssertEqual(game.headers.names, step.headerNames, item.name)
                XCTAssertEqual(Array(writePgn(game).utf8), Array(step.written.utf8), item.name)
            }
        }
    }
    func testSummarySearchAndCommentDisplayMatchTheWeb() throws {
        let fixture = try fixture()
        for item in fixture.summaries {
            XCTAssertEqual(gameTitle(item.headers), item.title)
            XCTAssertEqual(gameSubtitle(item.headers), item.subtitle)
            for query in item.queries { XCTAssertEqual(matchesSearch(item.headers, query.query), query.matches) }
        }
        for item in fixture.comments { XCTAssertEqual(displayComment(item.comment), item.displayed) }
    }
    func testGameCollectionOrderingMovementAndTiesMatchTheWeb() throws {
        let item = try fixture().library
        XCTAssertEqual(gameCollectionsOf(item.input), item.collections)
        XCTAssertEqual(gamesIn(item.input, "a"), item.games)
        XCTAssertEqual(moveGames(item.input, item.input.games, "b"), item.moved)
        for shift in item.shifts {
            let game = try XCTUnwrap(item.input.games.first { $0.id == shift.id })
            XCTAssertEqual(shiftGame(item.input, game, .up), shift.up)
            XCTAssertEqual(shiftGame(item.input, game, .down), shift.down)
        }
        // These are the stored boundary types; the derived tree is never cached.
        let cached = try JSONEncoder().encode(item.input)
        XCTAssertEqual(try JSONDecoder().decode(Library.self, from: cached), item.input)
    }
}
