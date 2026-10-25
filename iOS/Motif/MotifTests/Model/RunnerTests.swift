import XCTest
@testable import Motif

/// One test for every current runner.test.ts case (27).
final class RunnerTests: XCTestCase {
    func testAcceptsWellFormedMovesAndLowercasesThem() {
        XCTAssertEqual(parseUci("e2e4"), testMove("e2e4"))
        XCTAssertEqual(parseUci("E7E8Q"), testMove("e7e8q"))
        XCTAssertEqual(parseUci("  a2a1n "), testMove("a2a1n"))
    }
    func testRejectsGarbage() {
        for bad in ["", "e2", "e2e9", "j2j4", "e7e8k", "e2e4qq", "nonsense"] {
            XCTAssertNil(parseUci(bad), bad)
        }
    }
    func testStripsOnlyQueenPromotions() {
        XCTAssertEqual(stripQueenPromotion(testMove("e7e8q")), testMove("e7e8"))
        XCTAssertNil(stripQueenPromotion(testMove("e7e8n")))
        XCTAssertNil(stripQueenPromotion(testMove("e2e4")))
    }
    func testAcceptsTheOnlyLine() {
        let runner = PuzzleRunner(testPuzzle([["a1a8"]]))
        XCTAssertEqual(runner.submit(testMove("a1a8")), .correct(reply: nil, finished: true))
        XCTAssertTrue(runner.complete)
        XCTAssertEqual(runner.result, .solved)
    }
    func testRejectsAWrongMoveAndStaysOnTheSamePly() {
        let runner = PuzzleRunner(testPuzzle([["a1a8"]]))
        XCTAssertEqual(runner.submit(testMove("a1a7")), .wrong)
        XCTAssertEqual(runner.mistakes, 1)
        XCTAssertFalse(runner.complete)
        XCTAssertEqual(runner.submit(testMove("a1a8")), .correct(reply: nil, finished: true))
        XCTAssertEqual(runner.result, .failed)
    }
    func testPlaysTheScriptedReplyBetweenSolverMoves() {
        let runner = PuzzleRunner(testPuzzle([["d1h5", "g7g6", "h5g6"]]))
        XCTAssertEqual(runner.submit(testMove("d1h5")), .correct(reply: testMove("g7g6"), finished: false))
        XCTAssertEqual(runner.submit(testMove("h5g6")), .correct(reply: nil, finished: true))
        XCTAssertEqual(runner.result, .solved)
    }
    func testEndsOnTheOpponentsMoveWhenWrittenThatWay() {
        let runner = PuzzleRunner(testPuzzle([["a1a8", "g8g7"]]))
        XCTAssertEqual(runner.submit(testMove("a1a8")), .correct(reply: testMove("g8g7"), finished: true))
        XCTAssertTrue(runner.complete)
        XCTAssertEqual(runner.result, .solved)
        XCTAssertEqual(runner.accepted, [testMove("a1a8")])
    }
    func testTakesAReplyFromALongerLineWhenAShorterOneGotThereFirst() {
        let runner = PuzzleRunner(testPuzzle([["a1a8"], ["a1a8", "g8g7", "a8a7"]]))
        XCTAssertEqual(runner.submit(testMove("a1a8")), .correct(reply: testMove("g8g7"), finished: false))
        XCTAssertEqual(runner.submit(testMove("a8a7")), .correct(reply: nil, finished: true))
    }
    func testAcceptsEitherOfTwoSolutionsFromTheStart() {
        let puzzle = testPuzzle([["a1a8"], ["a1b1"]])
        for move in ["a1a8", "a1b1"] {
            XCTAssertEqual(PuzzleRunner(puzzle).submit(testMove(move)), .correct(reply: nil, finished: true))
        }
    }
    func testMergesSharedPrefixesAndDivergesLater() {
        let puzzle = testPuzzle([["d1h5", "g7g6", "h5g6"], ["d1h5", "g7g6", "h5e8"]])
        for finisher in ["h5g6", "h5e8"] {
            let runner = PuzzleRunner(puzzle)
            XCTAssertEqual(runner.submit(testMove("d1h5")), .correct(reply: testMove("g7g6"), finished: false))
            XCTAssertEqual(runner.submit(testMove(finisher)), .correct(reply: nil, finished: true))
            XCTAssertEqual(runner.result, .solved)
        }
    }
    func testKeepsThePlayedDefencesContinuationWhenAKeyMoveHasTwoAnswers() {
        let puzzle = testPuzzle([["a1a8", "g8g7", "a8a7"], ["a1a8", "h7h6", "a8h8"]])
        let first = PuzzleRunner(puzzle)
        XCTAssertEqual(first.submit(testMove("a1a8")), .correct(reply: testMove("g8g7"), finished: false))
        XCTAssertEqual(first.submit(testMove("a8a7")), .correct(reply: nil, finished: true))
        let second = PuzzleRunner(puzzle)
        XCTAssertEqual(second.submit(testMove("a1a8")), .correct(reply: testMove("g8g7"), finished: false))
        XCTAssertEqual(second.submit(testMove("a8h8")), .wrong)
    }
    func testKeepsEachDivergentLinesOwnOpponentReply() {
        let puzzle = testPuzzle([["a1a8", "g8g7", "a8a7"], ["a1b1", "g8f8", "b1b8"]])
        XCTAssertEqual(PuzzleRunner(puzzle).submit(testMove("a1a8")), .correct(reply: testMove("g8g7"), finished: false))
        XCTAssertEqual(PuzzleRunner(puzzle).submit(testMove("a1b1")), .correct(reply: testMove("g8f8"), finished: false))
    }
    func testMatchesAQueeningWrittenWithoutThePiece() {
        XCTAssertEqual(PuzzleRunner(testPuzzle([["e7e8"]])).submit(testMove("e7e8q")), .correct(reply: nil, finished: true))
    }
    func testDoesNotLetAnUnderpromotionSatisfyALineExpectingAQueen() {
        XCTAssertEqual(PuzzleRunner(testPuzzle([["e7e8"]])).submit(testMove("e7e8n")), .wrong)
    }
    func testRequiresTheExactPieceForUnderpromotionPuzzles() {
        let runner = PuzzleRunner(testPuzzle([["e7e8n"]]))
        XCTAssertEqual(runner.submit(testMove("e7e8q")), .wrong)
        XCTAssertEqual(runner.submit(testMove("e7e8n")), .correct(reply: nil, finished: true))
    }
    func testRefusesSubmissionsAfterTheLineEndsWithoutRecordingAMistake() {
        let runner = PuzzleRunner(testPuzzle([["a1a8"]]))
        runner.submit(testMove("a1a8"))
        XCTAssertEqual(runner.submit(testMove("a8a7")), .wrong)
        XCTAssertEqual(runner.mistakes, 0)
    }
    func testRecordsTheAcceptedMovesSoTheCardCanMarkTheLinePlayed() {
        let runner = PuzzleRunner(testPuzzle([["a1a8"], ["a1b1"]]))
        runner.submit(testMove("a1b1"))
        XCTAssertEqual(runner.accepted, [testMove("a1b1")])
    }
    func testRemembersNothingOnACleanSolve() {
        let runner = PuzzleRunner(testPuzzle([["a1a8"]]))
        runner.submit(testMove("a1a8"))
        XCTAssertEqual(runner.misses, [])
        XCTAssertEqual(runner.mistakes, 0)
    }
    func testTagsEachWrongMoveWithTheMoveItWasPlayedFor() {
        let runner = PuzzleRunner(testPuzzle([["d1h5", "g7g6", "h5g6"]]))
        ["d1h4", "d1h5", "h5h6", "h5h7", "h5g6"].forEach { runner.submit(testMove($0)) }
        XCTAssertEqual(runner.misses, [Miss(ply: 0, move: testMove("d1h4")),
                                     Miss(ply: 1, move: testMove("h5h6")), Miss(ply: 1, move: testMove("h5h7"))])
        XCTAssertEqual(runner.mistakes, 3)
        XCTAssertEqual(runner.result, .failed)
    }
    func testCountsSolverMovesNotThePliesOfTheLine() {
        let runner = PuzzleRunner(testPuzzle([["d1h5", "g7g6", "h5g6"]]))
        runner.submit(testMove("d1h5"))
        runner.submit(testMove("h5h6"))
        XCTAssertEqual(runner.misses, [Miss(ply: 1, move: testMove("h5h6"))])
    }
    func testListsARepeatedWrongMoveOncePerTry() {
        let runner = PuzzleRunner(testPuzzle([["a1a8"]]))
        runner.submit(testMove("a1a7")); runner.submit(testMove("a1a7"))
        XCTAssertEqual(runner.misses.count, 2)
        XCTAssertEqual(runner.misses.map(\.ply), [0, 0])
        XCTAssertEqual(runner.mistakes, 2)
    }
    func testRevealsOnlyAfterThreeWrongTries() {
        let runner = PuzzleRunner(testPuzzle([["a1a8"]]))
        for _ in 1...2 {
            runner.submit(testMove("a1a7"))
            XCTAssertFalse(runner.shouldRevealHint)
            XCTAssertNil(runner.revealHint())
        }
        runner.submit(testMove("a1a6"))
        XCTAssertTrue(runner.shouldRevealHint)
        XCTAssertEqual(runner.revealHint(), testMove("a1a8"))
        XCTAssertTrue(runner.hinted)
    }
    func testBudgetsPerPlyNotPerPuzzle() {
        let runner = PuzzleRunner(testPuzzle([["d1h5", "g7g6", "h5g6"]]))
        runner.submit(testMove("d1h4")); runner.submit(testMove("d1h3"))
        XCTAssertEqual(runner.wrongAtThisPly, 2)
        runner.submit(testMove("d1h5"))
        XCTAssertEqual(runner.wrongAtThisPly, 0)
        XCTAssertEqual(runner.mistakes, 2)
        runner.submit(testMove("h5h6"))
        XCTAssertFalse(runner.shouldRevealHint)
    }
    func testHintsWithTheEarliestDeclaredLine() {
        let runner = PuzzleRunner(testPuzzle([["a1a8"], ["a1b1"]]))
        for _ in 0..<3 { runner.submit(testMove("a1a7")) }
        XCTAssertEqual(runner.revealHint(), testMove("a1a8"))
    }
    func testIgnoresMoveCountersAndSolutionOrder() {
        XCTAssertEqual(contentKey(testContent([["a1a8"], ["a1b1"]])),
                       contentKey(testContent([["a1b1"], ["a1a8"]], fen: puzzleMateFEN.replacingOccurrences(of: "0 1", with: "9 42"))))
    }
    func testTreatsADifferentAnswerAsADifferentPuzzle() {
        XCTAssertNotEqual(contentKey(testContent([["a1a8"]])), contentKey(testContent([["a1b1"]])))
    }
    func testPlaysTheSideToMove() {
        XCTAssertEqual(solverSide(testPuzzle()), .white)
        XCTAssertEqual(solverSide(testPuzzle(fen: puzzleMateFEN.replacingOccurrences(of: " w ", with: " b "))), .black)
    }
}
