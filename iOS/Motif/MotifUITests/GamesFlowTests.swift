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
        app.buttons["From a FEN"].tap(); type("bad", into: app.descendants(matching: .any)["game-start-fen"])
        dismissKeyboard(); wait(app.descendants(matching: .any)["game-fen-error"]); expect(create, "isEnabled == false"); capture("new-game-invalid")
        app.buttons["Standard Start"].tap(); expect(create, "isEnabled == true"); create.tap()
        // The sheet's preview board is one element, so these squares are the viewer's.
        wait(overflow("game-actions")); wait(square("e2")); XCTAssertTrue(square("e2").label.contains("Pawn"))
    }
    func testStepPlayVariationCommentPromoteFlipAndExport() {
        launch("game:sample", extra: Self.analysisDefaults); wait(square("e2")); XCTAssertTrue(square("e2").label.contains("Pawn"))
        tap(button("game-next-move"), until: "label CONTAINS 'Pawn'", on: square("e4"))
        hold(button("game-previous-move"), until: "label CONTAINS 'empty'", on: square("e4")); move("c2", "c4"); wait(button("move-1"))
        overflow("game-actions").tap(); wait(button("game-edit-comment")); button("game-edit-comment").tap(); type("English idea", into: app.textViews["game-comment-text"])
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
        overflow("game-actions").tap(); let export = button("game-export-pgn", title: "Export PGN…"); wait(export); export.tap()
        let share = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Save to Files' OR label == 'Copy'")).firstMatch
        wait(share); capture("pgn-share-sheet")
    }
    /// D04: Select All / Deselect All and the bulk actions are titled toolbar items (side bar on IL, bottom
    /// bar on iPhone), found by title, and Move and Export still work from them.
    func testSelectAllAndBulkActionsWorkFromTheToolbarItems() {
        launch("game-select"); wait(button("game-select-done", title: "Done"))
        let titled = { (title: String) in self.app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch }
        expect(app.navigationBars.staticTexts["1 Selected"], "exists == true")
        let deselect = titled("Deselect All"); wait(deselect); deselect.tap()
        expect(app.navigationBars.staticTexts["Select Games"], "exists == true")
        let selectAll = titled("Select All"); wait(selectAll); selectAll.tap()
        expect(app.navigationBars.staticTexts["1 Selected"], "exists == true")
        let move = titled("Move"); wait(move); move.tap()
        let sheet = app.navigationBars["Move 1 Game"]; wait(sheet)
        let cancel = sheet.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == 'Close'")).firstMatch
        wait(cancel); cancel.tap(); expect(sheet, "exists == false")
        let export = titled("Export"); wait(export); export.tap()
        wait(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Save to Files'")).firstMatch)
        capture("bulk-export-share-sheet")
    }
    /// D04: Delete in the bulk bar asks, deletes the selection and leaves edit mode.
    func testBulkDeleteFromTheToolbarItem() {
        launch("game-select"); wait(button("game-select-done", title: "Done"))
        expect(app.navigationBars.staticTexts["1 Selected"], "exists == true")
        let delete = app.buttons.matching(NSPredicate(format: "label == 'Delete'")).firstMatch; wait(delete); delete.tap()
        let confirm = app.buttons["Delete 1 Game"]; wait(confirm); confirm.tap()
        wait(app.staticTexts["No Games"]); expect(button("game-select-done", title: "Done"), "exists == false")
    }
    func testUnsavedChangesAskBeforeLeavingAndSaveFromTheMenu() {
        launch("game:sample", extra: Self.analysisDefaults); wait(square("e2")); move("c2", "c4"); wait(button("move-1"))
        button("game-back").tap(); let alert = app.alerts["Save changes to this game?"]; wait(alert); capture("game-unsaved-alert")
        alert.buttons["Cancel"].tap(); XCTAssertTrue(button("move-1").exists)
        overflow("game-actions").tap(); wait(button("game-save")); button("game-save").tap()
        expect(button("game-back"), "exists == false"); XCTAssertTrue(button("move-1").exists)
        hold(button("game-previous-move"), until: "label CONTAINS 'empty'", on: square("c4")); move("d2", "d4"); wait(button("move-2")); button("game-back").tap(); wait(alert)
        alert.buttons["Discard Changes"].tap(); wait(button("game-row-sample-game"))
        button("game-row-sample-game").tap(); wait(button("move-1")); expect(button("move-2"), "exists == false")
    }
    func testUnreadableGameOffersCopyAndDelete() {
        launch("game-unreadable"); wait(app.staticTexts["Can't Read This Game"])
        XCTAssertTrue(app.descendants(matching: .any)["game-unreadable-pgn"].exists); capture("game-unreadable")
        // One query for both: the toast clears itself after 3s, which a loaded simulator can spend between two queries.
        button("game-unreadable-copy").tap(); wait(app.buttons.matching(NSPredicate(format: "identifier == 'toast' AND label == 'PGN copied.'")).firstMatch)
        button("game-unreadable-delete").tap()
        let confirms = app.buttons.matching(NSPredicate(format: "label == %@", "Delete game")); wait(confirms.firstMatch)
        let confirm = confirms.allElementsBoundByIndex.first(where: \.isHittable); XCTAssertNotNil(confirm, app.debugDescription); confirm?.tap()
        wait(button("game-row-sample-game")); expect(button("game-row-sample-unreadable"), "exists == false")
    }
    /// D05: on the Duo opened wide (IL) the Analysis view is two panes with a 504 pt board (decision 11),
    /// and Previous / Next Move are toolbar items in the side bar, clear of the board and the column.
    func testOpenWideAnalysisHasA504BoardAndStepsInTheToolbar() throws {
        try XCTSkipIf(pose != "IL", "Only the Duo opened wide (IL) has this layout")
        launch("game:sample"); wait(square("a1")); wait(square("h8"))
        let board = square("a1").frame.union(square("h8").frame)
        XCTAssertEqual(board.width, 504, accuracy: 1); XCTAssertEqual(board.height, 504, accuracy: 1)
        let list = app.descendants(matching: .any)["game-move-list"]; wait(list)
        XCTAssertGreaterThanOrEqual(list.frame.minX, board.maxX, "The moves sit beside the board")
        for id in ["game-previous-move", "game-next-move"] {
            let item = button(id); wait(item)
            XCTAssertFalse(item.frame.intersects(board), id)
            XCTAssertGreaterThanOrEqual(item.frame.minX, list.frame.maxX, "\(id) is in the trailing side bar")
        }
        tap(button("game-next-move"), until: "label CONTAINS 'Pawn'", on: square("e4"))
        hold(button("game-previous-move"), until: "label CONTAINS 'empty'", on: square("e4"))
    }
    func testOfflineGameAllowsEditingButNotSaving() throws {
        launch("game:sample", offline: true); wait(square("e2"))
        let banners = app.staticTexts.matching(identifier: "offline-banner"); wait(banners.firstMatch)
        // Require one visible banner, with neither navigation nor board overlap.
        let visible = banners.allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(visible.count, 1)
        let banner = try XCTUnwrap(visible.first)
        let title = app.navigationBars.staticTexts["White – Black"]; wait(title)
        XCTAssertGreaterThanOrEqual(banner.frame.minY, title.frame.maxY, app.debugDescription)
        XCTAssertLessThanOrEqual(banner.frame.maxY, square("a8").frame.minY)
        XCTAssertTrue(button("game-flip-board").isEnabled)
        tap(button("game-next-move"), until: "label CONTAINS 'Pawn'", on: square("e4")); capture("offline-game")
        overflow("game-actions").tap(); wait(button("game-edit-comment")); XCTAssertTrue(button("game-edit-comment").isEnabled)
        // Close the menu by tapping above the board, where nothing reacts.
        XCTAssertFalse(button("game-save").isEnabled); app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
        move("c7", "c5"); wait(button("game-back")); button("game-back").tap()
        let alert = app.alerts["Discard unsaved changes?"]; wait(alert); XCTAssertFalse(alert.buttons["Save"].exists); capture("game-offline-unsaved-alert")
        alert.buttons["Discard Changes"].tap(); wait(button("game-row-sample-game"))
    }
}
