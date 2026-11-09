import XCTest

/// The D02 shell: each tab is one `NavigationSplitView`, home list | selected collection.
@MainActor final class NavigationFlowTests: FlowTestCase {
    private func row(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    /// Open wide (IL): the sidebar opens a collection beside itself, then a puzzle, which hides the sidebar.
    func testSidebarOpensACollectionAndAPuzzleOnTheOpenDisplay() throws {
        try XCTSkipUnless(pose == "IL", "Two columns only show on the open display")
        launch(); let collection = row("collection-sample-back-rank"); wait(collection); collection.tap()
        let browse = button("browse-puzzles"); wait(browse)
        XCTAssertTrue(collection.isHittable, "The home list stays beside the collection\n\(app.debugDescription)")
        XCTAssertGreaterThanOrEqual(browse.frame.minX, collection.frame.maxX - 1, "The collection is in the detail column")
        capture("split-collection")
        browse.tap(); let puzzle = button("puzzle-sample-back-rank-0"); wait(puzzle); puzzle.tap()
        wait(button("puzzle-move-0"))
        // A pushed board screen hides the sidebar (`.detailOnly`).
        for _ in 0..<20 where collection.exists && collection.isHittable { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertFalse(collection.exists && collection.isHittable, "The sidebar still shows beside the puzzle\n\(app.debugDescription)")
        capture("split-puzzle")
    }
    /// D03, open wide (IL): the puzzle list fills the detail column beside the sidebar (526 pt in the
    /// canvases), within the readable width.
    func testPuzzleListFillsTheDetailColumnOnTheOpenDisplay() throws {
        try XCTSkipUnless(pose == "IL", "Two columns only show on the open display")
        launch(); let collection = row("collection-sample-back-rank"); wait(collection); collection.tap()
        let browse = button("browse-puzzles"); wait(browse); browse.tap()
        let puzzle = button("puzzle-sample-back-rank-0"); wait(puzzle)
        XCTAssertTrue(collection.isHittable, "The home list stays beside the puzzle list\n\(app.debugDescription)")
        XCTAssertGreaterThanOrEqual(puzzle.frame.minX, collection.frame.maxX - 1, "The puzzle list is in the detail column")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(puzzle.frame.width, 400, "The rows span the detail column\n\(app.debugDescription)")
        XCTAssertLessThanOrEqual(puzzle.frame.width, 672, "The rows stay within the readable width")
        XCTAssertLessThanOrEqual(puzzle.frame.maxX, window.maxX)
        capture("split-puzzle-list")
    }
    /// iPhone: the split view collapses to one stack, and Back from a collection clears the
    /// selection, so tapping the same row opens it again.
    func testBackFromACollectionClearsTheSelectionOnCompactWidth() throws {
        try XCTSkipIf(pose == "IL", "The open display shows both columns")
        launch(); let collection = row("collection-sample-back-rank"); wait(collection); collection.tap()
        let browse = button("browse-puzzles"); wait(browse)
        let back = app.navigationBars.buttons.matching(NSPredicate(format: "label == 'Puzzles' OR label == 'Back'")).firstMatch
        wait(back); back.tap()
        expect(browse, "exists == false"); wait(collection); collection.tap(); wait(browse)
    }
}
