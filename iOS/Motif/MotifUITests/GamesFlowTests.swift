import XCTest

@MainActor final class GamesFlowTests: FlowTestCase {
    func testPastePgnReportsBrokenGameAndKeepsValidGames() {
        launch("game-add")
        let text = app.textViews["game-import-text"]; wait(text); text.tap()
        text.typeText("[White \"Alpha\"]\n[Black \"Beta\"]\n1. e4 e5 *\n\n[White \"Bad\"]\n1. e4 e4 *\n\n[White \"Me\"]\n[Black \"Club friend\"]\n1. d4 d5 *")
        dismissKeyboard(); wait(app.staticTexts["2 games read · 1 couldn't be read"])
        capture("pgn-import-errors")
        let add = button("game-import-add"); if !add.isHittable { app.swipeUp() }; add.tap()
        wait(labelButton("Alpha – Beta")); XCTAssertTrue(labelButton("Me – Club friend").exists)
        let search = app.textFields["game-search"]; search.tap(); search.typeText("club"); dismissKeyboard()
        XCTAssertFalse(labelButton("Alpha – Beta").exists); XCTAssertTrue(labelButton("Me – Club friend").exists)
    }
    func testStepPlayVariationCommentPromoteFlipAndExport() {
        launch("game:sample"); wait(square("e2")); XCTAssertTrue(square("e2").label.contains("Pawn"))
        button("game-next-move").tap(); XCTAssertTrue(square("e4").label.contains("Pawn"))
        button("game-go-to-start").tap(); tap("c2"); tap("c4"); wait(button("move-1"))
        button("game-actions").tap(); wait(button("game-edit-comment")); button("game-edit-comment").tap(); let comment = app.textViews["game-comment-text"]; wait(comment); comment.tap(); comment.typeText("English idea")
        button("game-comment-save").tap(); wait(button("game-comment")); XCTAssertTrue(button("game-comment").label.contains("English idea"))
        // The comment card slides the list down as it appears; press again if the first press landed mid-move.
        let move = button("move-1"), promote = app.buttons["Make Main Line"]
        move.press(forDuration: 1.2); if !promote.waitForExistence(timeout: 3) { move.press(forDuration: 1.2) }; wait(promote)
        // The item's subtitle carries the count ("1 move"); system menus don't expose it to queries.
        wait(labelButton("Delete From Here")); capture("move-actions")
        app.buttons["Make Main Line"].tap()
        wait(button("move-0")); expectation(for: NSPredicate(format: "label CONTAINS 'c4'"), evaluatedWith: button("move-0")); waitForExpectations(timeout: 10)
        let before = square("a1").frame.minY
        button("game-flip-board").tap(); XCTAssertLessThan(square("a1").frame.minY, before)
        capture("annotated-game")
        button("game-actions").tap(); wait(button("game-export-pgn")); button("game-export-pgn").tap()
        let share = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Save to Files' OR label == 'Copy'")).firstMatch
        wait(share); capture("pgn-share-sheet")
    }
    func testOfflineGameOpensAndDisablesChanges() throws {
        launch("game:sample", offline: true); wait(square("e2"))
        let banners = app.staticTexts.matching(identifier: "offline-banner"); wait(banners.firstMatch)
        // Require one visible banner, with neither navigation nor board overlap.
        let visible = banners.allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(visible.count, 1)
        let banner = try XCTUnwrap(visible.first)
        let title = app.navigationBars.staticTexts["White – Black"]; wait(title)
        XCTAssertGreaterThanOrEqual(banner.frame.minY, title.frame.maxY, app.debugDescription)
        XCTAssertLessThanOrEqual(banner.frame.maxY, square("a8").frame.minY)
        XCTAssertFalse(button("game-flip-board").isEnabled)
        // CI has dropped this tap on a loaded simulator (delivered on the enabled button, no action);
        // tap again only while the board provably hasn't moved, then require the step as before.
        let next = button("game-next-move"); next.tap()
        let stepped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Pawn'"), object: square("e4"))
        if XCTWaiter.wait(for: [stepped], timeout: 5) != .completed, square("e2").label.contains("Pawn") { next.tap() }
        XCTAssertTrue(square("e4").label.contains("Pawn")); capture("offline-game")
        button("game-actions").tap(); wait(button("game-edit-comment")); XCTAssertFalse(button("game-edit-comment").isEnabled)
    }
}
