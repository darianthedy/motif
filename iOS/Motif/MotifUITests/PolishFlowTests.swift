import XCTest

/// Every list screen at the largest accessibility text size, the primary actions at AX5 on the
/// Duo opened wide (D10), and the newer states in dark mode.
@MainActor final class PolishFlowTests: FlowTestCase {
    func testListScreensKeepTextOnScreenAtLargestTextSize() {
        let routes: [(String?, String)] = [(nil, "solve-all"), ("collection", "solve-ordered"), ("puzzle-list", "puzzle-sample-back-rank-0"),
                                           ("game-collection", "game-row-sample-game"), ("game-select", "game-select-done")]
        for (route, ready) in routes {
            launch(route, extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
            wait(button(ready)); capture("ax-" + (route ?? "puzzles-home"))
            let width = app.windows.firstMatch.frame.maxX
            for text in app.cells.staticTexts.allElementsBoundByIndex where text.isHittable {
                XCTAssertLessThanOrEqual(text.frame.maxX, width + 1, "\(route ?? "puzzles-home"): \(text.label) runs off screen")
            }
        }
    }
    /// D10's "Done when": at AX5 on the Duo opened wide (IL) every primary action is still on screen,
    /// in the bar, the side bar or the overflow menu (toolbar items may move there at AX5, §9 D10).
    func testLargestTextReachesEveryPrimaryActionOpenWide() throws {
        try XCTSkipIf(pose != "IL", "Only the Duo opened wide (IL) runs the AX5 primary-action check")
        let ax5 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        // Puzzles home and a collection.
        launch(extra: ax5); wait(button("solve-all"))
        reach("solve-all", "Random From Everything"); reach("import-puzzles", "Import Puzzles"); reach("account", "Account")
        launch("collection", extra: ax5); reach("solve-ordered", "Solve in Order")
        // A session: the board, its bar items, then the result card's two actions.
        launch("session:all", extra: ax5); wait(square("a1"))
        reach("session-skip", "Skip"); reach("session-flag", "Flag"); reach("session-stop", "End Session")
        move("a1", "a8"); wait(app.staticTexts["result-verdict"])
        reach("result-continue", "Continue"); reach("result-analyze", "Analyze")
        capture("ax5-open-wide-result")
        // Puzzle detail: the replay steps, Flag, and the comment row at the end of the list.
        launch("puzzle-detail:sample-back-rank-1", extra: ax5); wait(square("a1"))
        reach("puzzle-next-move", "Next Move"); reach("puzzle-flag", "Flag")
        let list = app.descendants(matching: .any)["puzzle-detail-list"]; wait(list)
        let comment = button("puzzle-detail-comment", title: "Comment")
        for _ in 0..<5 where !(comment.exists && comment.isHittable) { list.swipeUp() }
        XCTAssertTrue(comment.isHittable, "The comment row can't be reached at AX5\n\(app.debugDescription)")
        capture("ax5-open-wide-puzzle-detail")
        // The Analysis view: the four bar items and the game menu.
        launch("game:sample", extra: ax5); wait(square("e2"))
        reach("game-previous-move", "Previous Move"); reach("game-next-move", "Next Move")
        reach("game-flip-board", "Flip Board"); reach("game-engine-lines", "Engine Lines")
        XCTAssertTrue(overflow("game-actions").waitForExistence(timeout: 10), "The game menu can't be reached at AX5")
        capture("ax5-open-wide-analysis")
        // A game collection.
        launch("game-collection", extra: ax5); wait(button("game-row-sample-game"))
        reach("add-games", "Add Games")
        XCTAssertTrue(overflow("game-collection-actions").waitForExistence(timeout: 10), "The collection menu can't be reached at AX5")
    }
    /// A primary action is on screen, or behind the overflow button when the bar runs out of room.
    private func reach(_ id: String, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let item = button(id, title: title)
        if item.waitForExistence(timeout: 10), item.isHittable { return }
        let more = app.buttons[FlowTestCase.overflowLabel]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "\(title) is neither on screen nor behind More\n\(app.debugDescription)", file: file, line: line)
        more.tap()
        let inMenu = button(id, title: title)
        XCTAssertTrue(inMenu.waitForExistence(timeout: 5) && inMenu.isHittable, "\(title) isn't in the overflow menu at AX5", file: file, line: line)
        // Close the menu without choosing anything.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
    }
    func testNewStatesInDarkMode() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        launch("puzzle-list-empty"); wait(app.staticTexts["No Flagged Puzzles"]); capture("dark-puzzle-list-empty")
        launch("game-select"); wait(button("game-select-done")); expect(app.navigationBars.staticTexts["1 Selected"], "exists == true"); capture("dark-game-select")
        launch("game-new"); wait(button("game-new-board")); capture("dark-game-new")
        launch("game-unreadable"); wait(app.staticTexts["Can't Read This Game"]); capture("dark-game-unreadable")
        launch("account"); wait(button("sign-out")); capture("dark-account")
    }
}
