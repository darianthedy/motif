import XCTest

@MainActor final class SolveFlowTests: FlowTestCase {
    func testSignInPasteImportAndCleanTapSolve() {
        launch(seeded: false)
        let email = app.textFields["auth-email"]; wait(email); email.tap(); email.typeText("solver@example.test")
        let password = app.secureTextFields["auth-password"]; password.tap(); password.typeText("anything")
        button("sign-in").tap(); wait(button("import-puzzles")); button("import-puzzles").tap()
        importPuzzle(#"{"collection":"UI puzzles","puzzles":[{"fen":"6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1","solutions":[["a1a8"]],"comment":"Hidden idea"}]}"#, name: "UI puzzles")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'square-'")).count, 64)
        XCTAssertEqual(square("a1").frame.width, square("a1").frame.height, accuracy: 1)
        XCTAssertFalse(app.staticTexts["puzzle-comment"].exists)
        move("a1", "d4"); XCTAssertFalse(app.staticTexts["result-verdict"].exists)
        move("a1", "a8"); wait(app.staticTexts["result-verdict"])
        XCTAssertEqual(app.staticTexts["result-verdict"].label, "Solved")
        XCTAssertEqual(app.staticTexts["puzzle-comment"].label, "Hidden idea")
        capture("clean-result")
        button("result-continue").tap(); wait(app.staticTexts["Session Complete"])
    }
    func testWrongMovesHintThenCleanDragRequiresContinue() {
        launch("session:all")
        for wrong in ["a7", "a6", "a5"] { move("a1", wrong) }
        wait(app.staticTexts["Not quite. Play the highlighted move."])
        move("a1", "a8"); wait(app.staticTexts["result-verdict"])
        XCTAssertTrue(app.staticTexts["result-verdict"].label.contains("Missed")); capture("hinted-result")
        button("result-continue").tap(); expect(square("d1"), "label CONTAINS 'Rook'")
        drag("d1", "d8"); wait(app.staticTexts["result-verdict"])
        XCTAssertEqual(app.staticTexts["result-verdict"].label, "Solved")
        XCTAssertTrue(square("d8").label.contains("Rook")); XCTAssertTrue(button("result-continue").exists)
        capture("drag-result")
    }
    func testAnalyzeOpensTheStartPositionThenReturnsToTheResult() {
        launch("session:all")
        move("a1", "a8"); wait(app.staticTexts["result-verdict"]); capture("result-with-analyze")
        tap(button("result-analyze"), until: "exists == true", on: button("game-next-move"))
        expect(square("a1"), "label CONTAINS 'Rook'"); XCTAssertTrue(app.navigationBars.staticTexts["Puzzle Analysis"].exists)
        tap(button("game-next-move"), until: "label CONTAINS 'Rook'", on: square("a8")); capture("puzzle-analysis")
        tap(button("game-actions"), until: "exists == true", on: button("game-save-as-game"))
        XCTAssertFalse(button("game-save").exists)
        button("game-save-as-game").tap(); wait(button("save-game-confirm")); capture("save-as-game")
        tap(button("save-game-confirm"), until: "exists == false")
        app.navigationBars.buttons.element(boundBy: 0).tap(); wait(button("result-continue"))
        XCTAssertEqual(app.staticTexts["result-verdict"].label, "Solved")
    }
    func testStopResumeAndSkipKeepProgress() {
        launch("collection"); wait(button("solve-ordered")); button("solve-ordered").tap(); wait(square("a1"))
        button("session-skip").tap()
        expect(square("d1"), "label CONTAINS 'Rook'")
        button("session-stop").tap(); wait(button("resume-session")); button("resume-session").tap(); wait(square("d1"))
        XCTAssertTrue(square("d1").label.contains("Rook")); XCTAssertFalse(app.staticTexts["result-verdict"].exists)
    }
    func testPromotionPickerCancelCostsNothing() {
        launch("import")
        importPuzzle(#"{"collection":"Promotion","puzzles":[{"fen":"7k/4P3/8/8/8/8/8/6K1 w - - 0 1","solutions":[["e7e8q"]]}]}"#, name: "Promotion")
        move("e7", "e8"); wait(button("choose-q")); XCTAssertFalse(button("choose-p").exists)
        capture("promotion-picker")
        button("picker-cancel").tap(); XCTAssertTrue(square("e7").label.contains("Pawn")); XCTAssertFalse(app.staticTexts["result-verdict"].exists)
        move("e7", "e8"); wait(button("choose-q")); button("choose-q").tap(); wait(app.staticTexts["result-verdict"])
        XCTAssertEqual(app.staticTexts["result-verdict"].label, "Solved")
    }
    func testMissingPiecePickerCancelAndWrongGuess() {
        launch("session:missing"); tap("g7"); XCTAssertFalse(button("choose-q").exists)
        place("g6"); wait(button("choose-p")); XCTAssertFalse(button("choose-k").exists); capture("placement-picker")
        button("picker-cancel").tap(); XCTAssertTrue(square("g6").label.contains("empty"))
        place("g6"); wait(button("choose-q")); button("choose-q").tap(); expect(square("g6"), "isSelected == false"); XCTAssertTrue(square("g6").label.contains("empty"))
        place("g6"); wait(button("choose-n")); button("choose-n").tap(); wait(app.staticTexts["result-verdict"])
        XCTAssertEqual(app.staticTexts["result-verdict"].label, "Missed · 1 wrong guess"); XCTAssertTrue(square("g6").label.contains("Knight"))
        XCTAssertTrue(app.staticTexts["puzzle-comment"].exists); capture("missing-result")
    }
    func testFinalOpponentReplyAppearsBeforeCompletion() {
        launch("import")
        importPuzzle(#"{"collection":"Forced reply","puzzles":[{"fen":"6k1/5p1p/8/8/8/8/8/3R2K1 w - - 0 1","solutions":[["d1d8","g8g7"]],"comment":"Only square."}]}"#, name: "Forced reply")
        drag("d1", "d8"); wait(app.staticTexts["result-verdict"])
        XCTAssertTrue(square("g7").label.contains("King")); XCTAssertTrue(square("g8").label.contains("empty"))
        XCTAssertEqual(app.staticTexts["result-verdict"].label, "Solved"); capture("forced-reply-result")
    }
}
