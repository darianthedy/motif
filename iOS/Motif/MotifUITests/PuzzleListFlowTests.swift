import XCTest

@MainActor final class PuzzleListFlowTests: FlowTestCase {
    func testSwipeFlagsAndDeletesAPuzzle() {
        launch("puzzle-list"); let first = button("puzzle-sample-back-rank-0"); settle(first); capture("puzzle-list")
        first.swipeLeft(); let flag = app.buttons["Flag"]; wait(flag); flag.tap()
        expect(first, "label CONTAINS 'Flagged'")

        let doomed = button("puzzle-sample-back-rank-1"); wait(doomed); doomed.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch; wait(delete); delete.tap()
        // The dialog's action can appear more than once in the tree; tap the one on screen.
        let confirms = app.buttons.matching(NSPredicate(format: "label == %@", "Delete Puzzle")); wait(confirms.firstMatch)
        let confirm = confirms.allElementsBoundByIndex.first(where: \.isHittable); XCTAssertNotNil(confirm, app.debugDescription); confirm?.tap()
        expect(doomed, "exists == false")
        XCTAssertTrue(first.exists)
    }
    /// Scopes on presentation (F23, Duo plan decision 19): with search active and nothing typed,
    /// the scope bar is there, and picking Flagged filters the list.
    func testScopeFiltersTheListWithAnEmptyQuery() {
        launch("puzzle-list"); let flagged = button("puzzle-sample-back-rank-0"); settle(flagged)
        flagged.swipeLeft(); let flag = app.buttons["Flag"]; wait(flag); flag.tap()
        expect(flagged, "label CONTAINS 'Flagged'")
        let other = button("puzzle-sample-back-rank-1"); wait(other)

        // On compact width the search field hides until the list is pulled down.
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 4) {
            app.swipeDown()
            if !field.waitForExistence(timeout: 3), app.buttons["Search"].exists { app.buttons["Search"].tap() }
        }
        wait(field); field.tap()
        let scopes = app.buttons.matching(NSPredicate(format: "label == %@", "Flagged"))
        if !scopes.firstMatch.waitForExistence(timeout: 5) { app.typeText("\n") }
        wait(scopes.firstMatch)
        let scope = scopes.allElementsBoundByIndex.first(where: \.isHittable) ?? scopes.firstMatch
        scope.tap(); capture("puzzle-list-scope-flagged")
        expect(other, "exists == false")
        XCTAssertTrue(flagged.exists, app.debugDescription)
        XCTAssertEqual((field.value as? String).map { $0 == field.placeholderValue || $0.isEmpty } ?? true, true,
                       "The query stays empty\n\(app.debugDescription)")
    }
    func testCollectionMenuImportsIntoThisCollection() {
        launch("collection"); let menu = overflow("collection-actions"); wait(menu); capture("collection")
        menu.tap(); let item = app.buttons["Import Into Collection…"]; wait(item); item.tap()
        wait(app.textViews["puzzle-import-text"])
    }
    /// D06: puzzle detail pins its board, 504 pt on the Duo opened wide (IL), with the list in the column
    /// beside it and the replay steps in the side bar (decision 18).
    func testOpenWidePuzzleDetailPinsA504BoardBesideTheList() throws {
        try XCTSkipIf(pose != "IL", "Only the Duo opened wide (IL) has this layout")
        launch("puzzle-detail:sample-back-rank-1"); wait(square("a1")); wait(square("h8"))
        let board = boardFrame()
        XCTAssertEqual(board.width, 504, accuracy: 1); XCTAssertEqual(board.height, 504, accuracy: 1)
        let list = app.descendants(matching: .any)["puzzle-detail-list"]; wait(list)
        XCTAssertGreaterThanOrEqual(list.frame.minX, board.maxX, "The list sits beside the board")
        let next = button("puzzle-next-move"); wait(next)
        XCTAssertFalse(next.frame.intersects(board)); XCTAssertGreaterThanOrEqual(next.frame.minX, list.frame.maxX, "Next Move is in the side bar")
        list.swipeUp(); XCTAssertEqual(boardFrame().minY, board.minY, accuracy: 1, "The list scrolls; the board stays")
    }
    func testPuzzleDetailReplaysSwitchesLinesFlagsCommentsCopiesAndDeletes() {
        launch("puzzle-list"); let row = button("puzzle-sample-back-rank-2"); settle(row)
        let first = button("puzzle-move-0"); tap(row, until: "exists == true", on: first); XCTAssertTrue(first.label.contains("Rb8"))
        tap(button("puzzle-next-move"), until: "isSelected == true", on: first)
        tap(button("puzzle-go-to-start"), until: "isSelected == false", on: first)
        tap(app.buttons["Line 2"], until: "label CONTAINS 'Ra1'", on: first)
        XCTAssertFalse(first.isSelected); tap(first, until: "isSelected == true"); capture("puzzle-detail")

        tap(button("puzzle-flag"), until: "label == 'Unflag'")

        // The Comment row can start below the fold, behind the replay bar (the bottom bar on an iPhone; the
        // side bar on the Duo sits beside it). isHittable still reports it as tappable there (a sliver shows
        // above the bar), so scroll the list, not the pinned board (D06), until the whole row clears the bar.
        let comment = button("puzzle-detail-comment"); wait(comment); let bar = button("puzzle-go-to-start")
        let list = app.descendants(matching: .any)["puzzle-detail-list"]; wait(list)
        let behindBar = { comment.frame.maxY > bar.frame.minY && comment.frame.minX < bar.frame.maxX && comment.frame.maxX > bar.frame.minX }
        for _ in 0..<3 where behindBar() { list.swipeUp() }
        XCTAssertFalse(behindBar(), app.debugDescription); let text = app.textViews["edit-puzzle-comment"]; tap(comment, until: "exists == true", on: text); capture("puzzle-detail-comment")
        text.tap(); text.typeText(" Rook lift."); button("puzzle-comment-save").tap()
        expect(button("puzzle-detail-comment"), "label CONTAINS 'Rook lift.'")

        overflow("puzzle-actions").tap(); let copy = app.buttons["Copy FEN"]; wait(copy); copy.tap()
        wait(app.buttons["toast"])

        overflow("puzzle-actions").tap(); let delete = app.buttons["Delete Puzzle"]; wait(delete); delete.tap()
        wait(app.staticTexts["Delete this puzzle from the library?"])
        let confirms = app.buttons.matching(NSPredicate(format: "label == %@", "Delete Puzzle")); wait(confirms.firstMatch)
        let confirm = confirms.allElementsBoundByIndex.first(where: \.isHittable); XCTAssertNotNil(confirm, app.debugDescription); confirm?.tap()
        wait(button("puzzle-sample-back-rank-0")); XCTAssertFalse(row.exists)
    }
}
