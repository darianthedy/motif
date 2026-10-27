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
        let search = app.searchFields.firstMatch; wait(search); search.tap(); search.typeText("club"); dismissKeyboard()
        expect(labelButton("Alpha – Beta"), "exists == false"); XCTAssertTrue(labelButton("Me – Club friend").exists)
    }
    func testNewGameSheetRejectsBadFenAndOpensTheViewer() {
        launch("game-collection"); let menu = button("add-games"); wait(menu); menu.tap()
        let item = app.buttons["New Game on Board…"]; wait(item); item.tap()
        let create = button("game-new-board"); wait(create); XCTAssertTrue(create.isEnabled)
        app.buttons["From a FEN"].tap(); let fen = app.descendants(matching: .any)["game-start-fen"]; wait(fen); fen.tap(); fen.typeText("bad")
        dismissKeyboard(); wait(app.descendants(matching: .any)["game-fen-error"]); expect(create, "isEnabled == false"); capture("new-game-invalid")
        app.buttons["Standard Start"].tap(); expect(create, "isEnabled == true"); create.tap()
        // The sheet's preview board is one element, so these squares are the viewer's.
        wait(button("game-actions")); wait(square("e2")); XCTAssertTrue(square("e2").label.contains("Pawn"))
    }
    func testStepPlayVariationCommentPromoteFlipAndExport() {
        launch("game:sample"); wait(square("e2")); XCTAssertTrue(square("e2").label.contains("Pawn"))
        tap(button("game-next-move"), until: "label CONTAINS 'Pawn'", on: square("e4"))
        tap(button("game-go-to-start"), until: "label CONTAINS 'Pawn'", on: square("e2")); move("c2", "c4"); wait(button("move-1"))
        button("game-actions").tap(); wait(button("game-edit-comment")); button("game-edit-comment").tap(); let comment = app.textViews["game-comment-text"]; wait(comment); comment.tap(); comment.typeText("English idea")
        button("game-comment-save").tap(); wait(button("game-comment")); expect(button("game-comment"), "label CONTAINS 'English idea'")
        // The comment card slides the list down as it appears; press again if the first press landed mid-move.
        let move = button("move-1"), promote = app.buttons["Make Main Line"]
        move.press(forDuration: 1.2); if !promote.waitForExistence(timeout: 3) { move.press(forDuration: 1.2) }; wait(promote)
        // The item's subtitle carries the count ("1 move"); system menus don't expose it to queries.
        wait(labelButton("Delete From Here")); capture("move-actions")
        app.buttons["Make Main Line"].tap()
        wait(button("move-0")); expect(button("move-0"), "label CONTAINS 'c4'")
        let before = square("a1").frame.minY
        button("game-flip-board").tap(); XCTAssertLessThan(square("a1").frame.minY, before)
        capture("annotated-game")
        button("game-actions").tap(); wait(button("game-export-pgn")); button("game-export-pgn").tap()
        let share = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Save to Files' OR label == 'Copy'")).firstMatch
        wait(share); capture("pgn-share-sheet")
    }
    func testUnreadableGameOffersCopyAndDelete() {
        launch("game-unreadable"); wait(app.staticTexts["Can't Read This Game"])
        XCTAssertTrue(app.descendants(matching: .any)["game-unreadable-pgn"].exists); capture("game-unreadable")
        button("game-unreadable-copy").tap(); wait(button("toast")); expect(button("toast"), "label == 'PGN copied.'")
        button("game-unreadable-delete").tap()
        let confirms = app.buttons.matching(NSPredicate(format: "label == %@", "Delete game")); wait(confirms.firstMatch)
        let confirm = confirms.allElementsBoundByIndex.first(where: \.isHittable); XCTAssertNotNil(confirm, app.debugDescription); confirm?.tap()
        wait(button("game-row-sample-game")); expect(button("game-row-sample-unreadable"), "exists == false")
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
        tap(button("game-next-move"), until: "label CONTAINS 'Pawn'", on: square("e4")); capture("offline-game")
        button("game-actions").tap(); wait(button("game-edit-comment")); XCTAssertFalse(button("game-edit-comment").isEnabled)
    }
}
