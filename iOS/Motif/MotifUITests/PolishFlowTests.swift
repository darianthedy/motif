import XCTest

/// Every list screen at the largest accessibility text size, and the newer states in dark mode.
@MainActor final class PolishFlowTests: FlowTestCase {
    func testListScreensKeepTextOnScreenAtLargestTextSize() {
        let routes: [(String?, String)] = [(nil, "solve-all"), ("collection", "collection-actions"), ("puzzle-list", "puzzle-sample-back-rank-0"),
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
