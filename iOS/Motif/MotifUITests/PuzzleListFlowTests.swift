import XCTest

@MainActor final class PuzzleListFlowTests: FlowTestCase {
    func testSwipeFlagsAndDeletesAPuzzle() {
        launch("puzzle-list"); let first = button("puzzle-sample-back-rank-0"); wait(first); capture("puzzle-list")
        first.swipeLeft(); let flag = app.buttons["Flag"]; wait(flag); flag.tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Flagged'"), evaluatedWith: first); waitForExpectations(timeout: 10)

        let doomed = button("puzzle-sample-back-rank-1"); wait(doomed); doomed.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch; wait(delete); delete.tap()
        // The dialog's action can appear more than once in the tree; tap the one on screen.
        let confirms = app.buttons.matching(NSPredicate(format: "label == %@", "Delete Puzzle")); wait(confirms.firstMatch)
        let confirm = confirms.allElementsBoundByIndex.first(where: \.isHittable); XCTAssertNotNil(confirm, app.debugDescription); confirm?.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: doomed); waitForExpectations(timeout: 10)
        XCTAssertTrue(first.exists)
    }
    func testCollectionMenuImportsIntoThisCollection() {
        launch("collection"); let menu = button("collection-actions"); wait(menu); capture("collection")
        menu.tap(); let item = app.buttons["Import Into Collection…"]; wait(item); item.tap()
        wait(app.textViews["puzzle-import-text"])
    }
}
