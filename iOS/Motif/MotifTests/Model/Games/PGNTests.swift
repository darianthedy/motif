import XCTest
@testable import Motif

/// One case for each pgn.test.ts case.
final class PGNTests: XCTestCase {
    func testKeepsHeadersMainLineVariationsCommentsAndAnnotations() throws {
        let game = try parsePgn(annotatedPGN)
        XCTAssertEqual(game.headers["Event"], "Club night")
        XCTAssertEqual(game.headers["White"], "Me")
        XCTAssertEqual(game.headers["Result"], "1-0")
        XCTAssertEqual(game.comment, "An old favourite.")
        XCTAssertEqual(testMainLine(game.moves), ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6"])
        let e4 = game.moves[0], c5 = game.moves[0].children[1]
        XCTAssertEqual(e4.children.map(\.san), ["e5", "c5"])
        XCTAssertEqual(c5.comment, "Sicilian")
        XCTAssertEqual(c5.children.map(\.san), ["Nf3", "c3"])
        XCTAssertEqual(c5.children[0].children.map(\.san), ["d6"])
        let nf3 = e4.children[0].children[0], bb5 = e4.children[0].children[0].children[0].children[0]
        XCTAssertEqual(nf3.nags, [1]); XCTAssertEqual(bb5.nags, [1])
        XCTAssertEqual(bb5.uci, testMove("f1b5"))
        XCTAssertEqual(bb5.children.map(\.san), ["a6", "Nf6"])
        XCTAssertEqual(bb5.children[0].children[0].comment, "to the end of the line")
    }
    func testRoundTripsThroughTheWriter() throws {
        let game = try parsePgn(annotatedPGN), written = writePgn(try parsePgn(annotatedPGN))
        XCTAssertEqual(try parsePgn(written), game)
        XCTAssertEqual(writePgn(try parsePgn(written)), written)
    }
    func testNumbersBlackAfterAnythingBetweenItAndWhite() throws {
        let written = writePgn(try parsePgn(annotatedPGN))
        let movetext = cleanPgnText(written)
        XCTAssertTrue(movetext.contains("{An old favourite.} 1. e4 e5 (1... c5 {Sicilian} 2. Nf3 (2. c3) 2... d6)"))
        XCTAssertTrue(movetext.contains("2. Nf3 $1 Nc6 3. Bb5 $1 a6 (3... Nf6 4. O-O) 4. Ba4"))
        XCTAssertTrue(written.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("1-0"))
        XCTAssertTrue(written.components(separatedBy: "\n").allSatisfy { $0.utf16.count <= 80 })
    }
    func testStartsFromAFENHeaderWithBlackToMove() throws {
        let fen = "6k1/5ppp/8/8/8/8/5PPP/R5K1 b - - 0 30"
        let game = try parsePgn("[SetUp \"1\"]\n[FEN \"\(fen)\"]\n\n30... h6 31. Ra8+ Kh7 *")
        XCTAssertEqual(game.startFen, fen)
        XCTAssertEqual(testMainLine(game.moves), ["h6", "Ra8+", "Kh7"])
        XCTAssertTrue(writePgn(game).contains("30... h6 31. Ra8+ Kh7 *"))
    }
    func testKeepsACommentBeforeAVariationsFirstMove() throws {
        let game = try parsePgn("1. e4 ({or} 1. d4 d5) e5 *")
        XCTAssertEqual(game.moves[1].before, "or")
        XCTAssertTrue(writePgn(game).contains("1. e4 ({or} 1. d4 d5) 1... e5 *"))
    }
    func testReadsLooselyWrittenMoves() throws {
        let game = try parsePgn("1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5 4.0-0 Nf6!? *")
        XCTAssertEqual(testMainLine(game.moves), ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "O-O", "Nf6"])
        XCTAssertEqual(testMainNodes(game.moves)[7].nags, [5])
    }
    func testReadsAnnotationSymbolsWrittenAsWords() throws {
        let game = try parsePgn("1. e4 e5 = 2. Nf3 ⩱ (2. Qh5 ⨀) Nc6 +/- 3. Bb5 -+ *")
        XCTAssertEqual(testMainNodes(game.moves).map(\.nags), [[], [10], [15], [16], [19]])
        XCTAssertEqual(game.moves[0].children[0].children[1].nags, [22])
        XCTAssertTrue(cleanPgnText(writePgn(game)).contains("1. e4 e5 $10 2. Nf3 $15 (2. Qh5 $22) 2... Nc6 $16"))
    }
    func testTakesTheMovetextResultWithoutAHeader() throws {
        XCTAssertEqual(try parsePgn("1. f3 e5 2. g4 Qh4# 0-1").headers["Result"], "0-1")
        XCTAssertEqual(try parsePgn("1. e4").headers["Result"], "*")
    }
    func testReadsABareFENAsAGameWithNoMoves() {
        let fen = "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"
        let file = parsePgnFile("  \(fen)\n")
        XCTAssertEqual(file.errors, []); XCTAssertEqual(file.games.count, 1)
        XCTAssertEqual(file.games.first?.startFen, fen)
        XCTAssertEqual(file.games.first?.moves, [])
        XCTAssertEqual(file.games.first?.headers["FEN"], fen)
    }
    func testSplitsGamesAndSkipsOneWithAnIllegalMove() {
        let file = parsePgnFile("[White \"A\"]\n\n1. e4 e5 1-0\n\n[White \"B\"]\n\n1. e4 e4 *\n\n[White \"C\"]\n\n1. d4 *\n")
        XCTAssertEqual(file.games.map { $0.headers["White"] }, ["A", "C"])
        XCTAssertEqual(file.errors, [PgnError(game: 2, message: "1... e4 is not a legal move")])
    }
    func testSplitsGamesWithoutAResultBetweenThem() {
        let file = parsePgnFile("[White \"A\"]\n\n1. e4\n[White \"B\"]\n\n1. d4\n")
        XCTAssertEqual(file.games.map { testMainLine($0.moves) }, [["e4"], ["d4"]])
    }
    func testReportsUnbalancedVariationsAndUnclosedComments() {
        XCTAssertTrue(parsePgnFile("1. e4 (1. d4").errors.first?.message.contains("never closed") == true)
        XCTAssertTrue(parsePgnFile("1. e4 ) *").errors.first?.message.contains("no (") == true)
        XCTAssertTrue(parsePgnFile("1. e4 {oops").errors.first?.message.contains("never closed") == true)
    }
    func testReadsAnEmptyFileAsNoGames() {
        XCTAssertEqual(parsePgnFile("  \n"), PgnFile())
    }
    func testNewGameHasSevenHeadersAndTheStartingPosition() throws {
        let game = newGame()
        XCTAssertEqual(game.headers.names, ["Event", "Site", "Date", "Round", "White", "Black", "Result"])
        XCTAssertEqual(game.startFen, Board.defaultPosition)
        XCTAssertEqual(try parsePgn(writePgn(game)), game)
    }
    func testNewGameRecordsASetupPosition() throws {
        let fen = "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"
        let game = newGame(fen)
        XCTAssertEqual(game.headers["SetUp"], "1"); XCTAssertEqual(game.headers["FEN"], fen)
        XCTAssertEqual(try parsePgn(writePgn(game)), game)
    }
    func testEscapesQuotesInHeadersAndBracesInComments() throws {
        var game = newGame()
        game.comment = "a {b} c"
        game.headers["Event"] = "The \"Open\""
        let read = try parsePgn(writePgn(game))
        XCTAssertEqual(read.headers["Event"], "The \"Open\"")
        XCTAssertEqual(read.comment, "a {b) c")
    }
    func testReadsOnlyTheLeadingHeaderBlock() throws {
        XCTAssertEqual(readHeaders(writePgn(try parsePgn(annotatedPGN))), try parsePgn(annotatedPGN).headers)
        XCTAssertEqual(readHeaders("[White \"A \\\"B\\\"\"]\n\n1. e4 [x \"y\"] *"), PgnHeaders([("White", "A \"B\"")]))
        XCTAssertEqual(readHeaders("1. e4 *"), PgnHeaders())
    }
}
