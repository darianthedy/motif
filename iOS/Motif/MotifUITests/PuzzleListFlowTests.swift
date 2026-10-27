import XCTest

@MainActor final class PuzzleListFlowTests: FlowTestCase {
    func testSwipeFlagsAndDeletesAPuzzle() {
        launch("puzzle-list"); let first = button("puzzle-sample-back-rank-0"); wait(first); capture("puzzle-list")
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
    func testCollectionMenuImportsIntoThisCollection() {
        launch("collection"); let menu = button("collection-actions"); wait(menu); capture("collection")
        menu.tap(); let item = app.buttons["Import Into Collection…"]; wait(item); item.tap()
        wait(app.textViews["puzzle-import-text"])
    }
    func testPuzzleDetailReplaysSwitchesLinesFlagsCommentsCopiesAndDeletes() {
        launch("puzzle-list"); let row = button("puzzle-sample-back-rank-2"); wait(row); row.tap()
        let first = button("puzzle-move-0"); wait(first); XCTAssertTrue(first.label.contains("Rb8"))
        tap(button("puzzle-next-move"), until: "isSelected == true", on: first)
        tap(button("puzzle-go-to-start"), until: "isSelected == false", on: first)
        tap(app.buttons["Line 2"], until: "label CONTAINS 'Ra1'", on: first)
        XCTAssertFalse(first.isSelected); tap(first, until: "isSelected == true"); capture("puzzle-detail")

        tap(button("puzzle-flag"), until: "label == 'Unflag'")

        // The Comment row starts below the fold, behind the replay bar. isHittable still reports it as
        // tappable there (a sliver shows above the bar), so scroll until the whole row clears the bar.
        let comment = button("puzzle-detail-comment"); wait(comment); let bar = button("puzzle-go-to-start")
        for _ in 0..<3 where comment.frame.maxY > bar.frame.minY { app.swipeUp() }
        XCTAssertLessThanOrEqual(comment.frame.maxY, bar.frame.minY, app.debugDescription); let text = app.textViews["edit-puzzle-comment"]; tap(comment, until: "exists == true", on: text); capture("puzzle-detail-comment")
        text.tap(); text.typeText(" Rook lift."); button("puzzle-comment-save").tap()
        expect(button("puzzle-detail-comment"), "label CONTAINS 'Rook lift.'")

        button("puzzle-actions").tap(); let copy = app.buttons["Copy FEN"]; wait(copy); copy.tap()
        wait(app.buttons["toast"])

        button("puzzle-actions").tap(); let delete = app.buttons["Delete Puzzle"]; wait(delete); delete.tap()
        wait(app.staticTexts["Delete this puzzle from the library?"])
        let confirms = app.buttons.matching(NSPredicate(format: "label == %@", "Delete Puzzle")); wait(confirms.firstMatch)
        let confirm = confirms.allElementsBoundByIndex.first(where: \.isHittable); XCTAssertNotNil(confirm, app.debugDescription); confirm?.tap()
        wait(button("puzzle-sample-back-rank-0")); XCTAssertFalse(row.exists)
    }
}
