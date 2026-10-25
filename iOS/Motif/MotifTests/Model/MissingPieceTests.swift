import XCTest
@testable import Motif

/// One test for every missing-piece.test.ts case (21).
final class MissingPieceTests: XCTestCase {
    private func puzzle() -> Puzzle { testPuzzle(fen: missingPieceFEN, addPiece: missingKnight) }
    func testReadsTheColourOffTheCaseAsAFENDoes() {
        XCTAssertEqual(parsePlacement("Ng6"), missingKnight)
        XCTAssertEqual(parsePlacement("ng6"), Placement(color: .black, type: .knight, square: "g6"))
        XCTAssertEqual(parsePlacement("  Q f8 "), Placement(color: .white, type: .queen, square: "f8"))
    }
    func testAcceptsAnExplicitColourForAnyoneInTheHabitOfWritingSAN() {
        XCTAssertEqual(parsePlacement("bNg6"), Placement(color: .black, type: .knight, square: "g6"))
        XCTAssertEqual(parsePlacement("wng6"), missingKnight)
        XCTAssertEqual(parsePlacement("bg6"), Placement(color: .black, type: .bishop, square: "g6"))
        XCTAssertEqual(parsePlacement("bBg6"), Placement(color: .black, type: .bishop, square: "g6"))
    }
    func testRejectsAnythingElse() {
        for bad in ["", "g6", "Xg6", "Ng9", "Nj6", "Ng6g7", "knight g6"] { XCTAssertNil(parsePlacement(bad)) }
    }
    func testRoundTripsThroughItsWrittenForm() throws {
        for text in ["Ng6", "ng6", "Qf8", "pa2"] { XCTAssertEqual(placementText(try XCTUnwrap(parsePlacement(text))), text) }
    }
    func testPutsThePieceOnTheSquare() throws {
        let next = try XCTUnwrap(Board.withPiece(missingPieceFEN, missingKnight))
        XCTAssertEqual(Board.pieceAt(next, "g6"), Board.Piece(square: "g6", type: .knight, color: .white))
        XCTAssertEqual(next.split(separator: " ")[1], "b")
    }
    func testRefusesASquareThatIsTakenRatherThanReplacingIt() {
        XCTAssertNil(Board.withPiece(missingPieceFEN, Placement(color: .white, type: .knight, square: "g7")))
    }
    func testRefusesPositionsThatAreNotPositions() {
        XCTAssertNil(Board.withPiece(missingPieceFEN, Placement(color: .white, type: .pawn, square: "e8")))
        XCTAssertNil(Board.withPiece(missingPieceFEN, Placement(color: .white, type: .king, square: "e4")))
    }
    func testFindsTheOnePieceThatMatesWhichMakesThePuzzleFair() {
        XCTAssertEqual(Board.matingPlacements(missingPieceFEN, .white).map(placementText), ["Ng6"])
    }
    func testIsTheKindDerivedRatherThanDeclared() {
        XCTAssertTrue(isMissingPiece(puzzle()))
        XCTAssertFalse(isMissingPiece(testPuzzle()))
    }
    func testSeparatesTwoPuzzlesThatDifferOnlyInTheAnswer() {
        var other = puzzle()
        other.addPiece = Placement(color: .white, type: .queen, square: "g6")
        XCTAssertNotEqual(contentKey(puzzle()), contentKey(other))
    }
    func testKeysAnOrdinaryPuzzleByPositionAndLineAlone() {
        XCTAssertEqual(contentKey(testContent([["g8g7"]], fen: missingPieceFEN)),
                       "\(normalizeFen(missingPieceFEN))/g8g7/-")
    }
    func testIsAnsweredForTheColourOfThePieceNotTheSideToMove() {
        XCTAssertEqual(solverSide(puzzle()), .white)
    }
    func testSolvesOnTheRightPieceAndTheRightSquare() {
        let runner = MissingPieceRunner(puzzle(), missingKnight)
        XCTAssertEqual(runner.submit("g6", .knight), .correct)
        XCTAssertTrue(runner.complete)
        XCTAssertEqual(runner.result, .solved)
    }
    func testCountsTheRightSquareWithTheWrongPieceAsAMiss() {
        let runner = MissingPieceRunner(puzzle(), missingKnight)
        XCTAssertEqual(runner.submit("g6", .queen), .wrong)
        XCTAssertEqual(runner.submit("f6", .knight), .wrong)
        XCTAssertEqual(runner.mistakes, 2)
        XCTAssertFalse(runner.complete)
        runner.submit("g6", .knight)
        XCTAssertEqual(runner.result, .failed)
    }
    func testKeepsTheWrongGuessesThemselvesForTheCardAtTheEnd() {
        let runner = MissingPieceRunner(puzzle(), missingKnight)
        runner.submit("g6", .queen); runner.submit("f6", .knight); runner.submit("g6", .knight)
        XCTAssertEqual(runner.wrongGuesses, [Placement(color: .white, type: .queen, square: "g6"),
                                           Placement(color: .white, type: .knight, square: "f6")])
    }
    func testRevealsTheAnswerAfterTheSameThreeTriesAMovePuzzleAllows() {
        let runner = MissingPieceRunner(puzzle(), missingKnight)
        for _ in 0..<(ATTEMPTS_BEFORE_HINT - 1) { runner.submit("a3", .queen) }
        XCTAssertFalse(runner.shouldRevealHint)
        XCTAssertNil(runner.revealHint())
        XCTAssertFalse(runner.hinted)
        runner.submit("a3", .queen)
        XCTAssertTrue(runner.shouldRevealHint)
        XCTAssertEqual(runner.revealHint(), missingKnight)
        XCTAssertTrue(runner.hinted)
    }
    func testReadsTheFormatAsWritten() throws {
        let result = importEntry(#"{ "id": 187, "fen": "\#(missingPieceFEN)", "solutions": [], "tags": ["missingPiece"], "comment": "Add a knight and it's mate", "add_piece": "Ng6" }"#)
        XCTAssertEqual(result.rejected, [])
        let entry = try XCTUnwrap(result.groups.first?.puzzles.first)
        XCTAssertEqual(entry.solutions, [])
        XCTAssertEqual(entry.addPiece, missingKnight)
        XCTAssertEqual(entry.sourceId, "187")
        XCTAssertEqual(entry.comment, "Add a knight and it's mate")
    }
    func testRejectsAPlacementThatCannotBeMade() {
        for (field, reason) in [
            (#""add_piece": "Kg6""#, "king cannot be added"),
            (#""add_piece": "Ng7""#, "g7 is not empty"),
            (#""add_piece": "Pg1""#, "does not make a legal position"),
            (#""add_piece": "knight to g6""#, "Malformed piece"),
            (#""add_piece": 7"#, "Malformed piece"),
        ] {
            let result = importEntry(#"{ "fen": "\#(missingPieceFEN)", "solutions": [], \#(field) }"#)
            XCTAssertEqual(result.groups.first?.puzzles.count, 0)
            XCTAssertTrue(result.rejected.first?.reason.contains(reason) == true, field)
        }
    }
    func testRefusesToBeBothKindsAtOnce() {
        let result = importEntry(#"{ "fen": "\#(missingPieceFEN)", "solutions": [["g8g7"]], "add_piece": "Ng6" }"#)
        XCTAssertTrue(result.rejected.first?.reason.contains("can carry no solution") == true)
    }
    func testStillWantsASolutionFromAnOrdinaryPuzzle() {
        XCTAssertEqual(importEntry(#"{ "fen": "\#(missingPieceFEN)", "solutions": [] }"#).rejected.first?.reason, "Puzzle has no solution")
    }
    func testImportsTheSampleFileWhole() throws {
        let fixture = try loadPuzzleFixture("import", as: ImportFixture.self)
        let sample = try XCTUnwrap(fixture.cases.first { $0.name == "sample-missing-piece" })
        let result = importJson(sample.text)
        XCTAssertEqual(result.rejected, [])
        XCTAssertEqual(importedPuzzles(result).count, 3)
        XCTAssertEqual(result.collectionName, "Missing pieces")
        for entry in importedPuzzles(result) {
            let placement = try XCTUnwrap(entry.addPiece)
            XCTAssertEqual(Board.matingPlacements(entry.fen, placement.color).map(placementText), [placementText(placement)])
        }
    }
}
