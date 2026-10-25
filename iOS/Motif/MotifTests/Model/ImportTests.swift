import XCTest
@testable import Motif

/// One test for every current import/import.test.ts case (18).
final class ImportTests: XCTestCase {
    private var book: String {
        #"""
        [
          {"collection":"Mate in one","puzzles":[
            {"id":1,"fen":"kr6/1p6/p7/4b3/8/8/1P4BP/R6K w - - 0 1","solutions":[["a1a6"]],"tags":["mateIn1"],"comment":"The pin is mightier than the sword"},
            {"id":2,"fen":"r2B3k/5p1p/8/8/8/b7/7P/K5R1 w - - 0 1","solutions":[["d8f6"]],"tags":["mateIn1"]}]},
          {"collection":"Mate in two","puzzles":[
            {"id":58,"fen":"1r1k4/2R4R/8/8/8/6pP/PPP4q/K1B5 w - - 0 1","solutions":[["c1g5","d8e8","h7h8"]],"tags":["mateIn2"]}]}
        ]
        """#
    }
    func testAcceptsRealPositions() {
        XCTAssertTrue(Board.isValidFen(puzzleMateFEN))
        XCTAssertTrue(Board.isValidFen("7k/5ppp/8/8/8/8/8/R5K1 w - - 0 1"))
    }
    func testCatchesTheCommonBreakages() {
        for fen in [
            "6k1/5ppp/8/8/8/8/8 w - - 0 1",
            "6k1/5ppp/8/8/8/8/8/R5K1 x - - 0 1",
            "8k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1",
            "6k1/5ppp/8/8/8/8/8/R5R1 w - - 0 1",
            "6k1/5ppp/8/8/8/8/8/R5K1x w - - 0 1",
        ] { XCTAssertFalse(Board.isValidFen(fen), fen) }
    }
    func testReadsThePuzzleNumberFromIdAsANumberOrString() {
        let result = importEntry(#"{ "id":187, "fen":"\#(puzzleMateFEN)", "solutions":[["a1a8"]] }, { "id":"12b", "fen":"\#(puzzleMateFEN)", "solutions":[["a1a7"]] }"#)
        XCTAssertEqual(importedPuzzles(result).map(\.sourceId), ["187", "12b"])
    }
    func testImportsAWellFormedFile() throws {
        let result = importEntry(#"{ "fen":"\#(puzzleMateFEN)", "solutions":[["a1a8"]], "tags":["backRank"], "comment":"No luft.", "rating":900 }"#, collection: "Back-rank mates")
        XCTAssertEqual(result.collectionName, "Back-rank mates")
        XCTAssertEqual(importedPuzzles(result).count, 1)
        let entry = try XCTUnwrap(importedPuzzles(result).first)
        XCTAssertEqual(entry.tags, ["backRank"])
        XCTAssertEqual(entry.comment, "No luft.")
        XCTAssertEqual(entry.rating, 900)
    }
    func testRejectsBadEntriesWithReasonsInsteadOfDroppingThem() {
        let result = importEntry(#"""
        { "fen":"not-a-fen", "solutions":[["a1a8"]] },
        { "fen":"\#(puzzleMateFEN)", "solutions":[] },
        { "fen":"\#(puzzleMateFEN)", "solutions":[["a1a8","g8g7"]] },
        { "fen":"\#(puzzleMateFEN)", "solutions":[["a1z9"]] }
        """#)
        XCTAssertEqual(importedPuzzles(result), [])
        XCTAssertEqual(result.rejected.map(\.reason), [
            "Malformed FEN", "Puzzle has no solution", "Move g8g7 is illegal at ply 2",
            "Solution contains a malformed move",
        ])
    }
    func testAcceptsALineThatEndsOnTheOpponentsForcedReply() throws {
        let result = importEntry(#"{ "fen":"6k1/5p1p/8/8/8/8/8/3R2K1 w - - 0 1", "solutions":[["d1d8","g8g7"]], "comment":"Only square." }"#)
        XCTAssertEqual(result.rejected, [])
        let content = try XCTUnwrap(importedPuzzles(result).first)
        XCTAssertEqual(content.solutions[0], ["d1d8", "g8g7"].map(testMove))
        let runner = PuzzleRunner(Puzzle(content: content, id: "p1", collectionId: "c1", position: 0, addedAt: 0))
        XCTAssertEqual(runner.submit(testMove("d1d8")), .correct(reply: testMove("g8g7"), finished: true))
    }
    func testReportsInvalidJSONRatherThanThrowing() {
        let result = importJson("{ not json")
        XCTAssertTrue(result.rejected.first?.reason.contains("Not valid JSON") == true)
    }
    func testKeepsAPuzzleListedTwiceOnceWhereItFirstAppeared() {
        let result = importEntry(#"""
        { "fen":"\#(puzzleMateFEN)", "solutions":[["a1a8"]], "tags":["a"] },
        { "fen":"7k/5ppp/8/8/8/8/8/R6K w - - 0 1", "solutions":[["a1a8"]] },
        { "fen":"6k1/5ppp/8/8/8/8/8/R5K1 w - - 5 9", "solutions":[["a1a8"]], "tags":["b"] }
        """#)
        XCTAssertEqual(importedPuzzles(result).map(\.tags), [["b"], []])
    }
    func testKeepsTheSamePuzzleInTwoCollectionsTwice() {
        let entry = #"{ "fen":"\#(puzzleMateFEN)", "solutions":[["a1a8"]] }"#
        let result = importJson(#"[{"collection":"A","puzzles":[\#(entry)]},{"collection":"B","puzzles":[\#(entry)]}]"#)
        XCTAssertEqual(result.groups.map { $0.puzzles.count }, [1, 1])
    }
    func testReadsEveryChapterAsItsOwnGroup() {
        let result = importJson(book)
        XCTAssertEqual(result.groups.map(\.name), ["Mate in one", "Mate in two"])
        XCTAssertEqual(result.groups.map { $0.puzzles.count }, [2, 1])
        XCTAssertEqual(importedPuzzles(result).count, 3)
    }
    func testKeepsTheBookNumberAsTheSourceId() {
        let result = importJson(book)
        XCTAssertEqual(result.groups.first?.puzzles.first?.sourceId, "1")
        XCTAssertEqual(result.groups.last?.puzzles.first?.sourceId, "58")
    }
    func testLeavesCollectionNameUnsetForSeveralGroups() {
        XCTAssertNil(importJson(book).collectionName)
    }
    func testNumbersRejectionsAcrossTheWholeFileNotPerChapter() {
        let result = importJson(#"""
        [{"collection":"A","puzzles":[{"fen":"\#(puzzleMateFEN)","solutions":[["a1a8"]]}]},
         {"collection":"B","puzzles":[{"fen":"nonsense","solutions":[["a1a8"]]}]}]
        """#)
        XCTAssertEqual(result.rejected, [ImportRejection(index: 1, reason: "Malformed FEN")])
    }
    func testStillHandlesAPlainSingleCollectionObject() {
        let result = importEntry(#"{ "fen":"\#(puzzleMateFEN)", "solutions":[["a1a8"]] }"#, collection: "Solo")
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.collectionName, "Solo")
    }
    func testRejectsAFirstMoveIllegalInThePosition() {
        let result = importEntry(#"{ "fen":"\#(puzzleMateFEN)", "solutions":[["a1b2"]] }"#)
        XCTAssertEqual(importedPuzzles(result), [])
        XCTAssertEqual(result.rejected.first?.reason, "Move a1b2 is illegal at ply 1")
    }
    func testRejectsAMoveThatBecomesIllegalLaterInTheLine() {
        let result = importEntry(#"{ "fen":"2rrk1n1/1nQ1p2N/pB5p/6p1/qP3p2/2P4P/P3BPP1/3R2K1 w - - 0 1", "solutions":[["c7d8","e8d8","d1d8"]] }"#)
        XCTAssertEqual(importedPuzzles(result), [])
        XCTAssertEqual(result.rejected.first?.reason, "Move e8d8 is illegal at ply 2")
    }
    func testAcceptsALineLegalThroughout() {
        let result = importEntry(#"{ "fen":"1r1k4/2R4R/8/8/8/6pP/PPP4q/K1B5 w - - 0 1", "solutions":[["c1g5","d8e8","h7h8"]] }"#)
        XCTAssertEqual(importedPuzzles(result).count, 1)
        XCTAssertEqual(result.rejected, [])
    }
    func testValidatesEachLineOfAMultiSolutionPuzzle() {
        let result = importEntry(#"{ "fen":"\#(puzzleMateFEN)", "solutions":[["a1a8"],["a1b2"]] }"#)
        XCTAssertEqual(importedPuzzles(result), [], "One bad line rejects the puzzle")
    }
}
