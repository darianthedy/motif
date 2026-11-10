import XCTest

/// D11: the iPad (ios-ci's `ipad` destination, an 11-inch iPad turned to landscape) gets the regular-width
/// layouts with no iPad-only screens: the home list beside the selected collection (decision 12), and the
/// Analysis view as two panes whose board fits the window without scrolling (`BoardLayout`, 672 pt at
/// 1194 × 834 with the bars; `BoardLayoutTests.testIPadFollowsTheSameRule`).
@MainActor final class IPadFlowTests: FlowTestCase {
    private func row(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testIPadShowsTheSidebarBesideTheDetail() throws {
        try XCTSkipUnless(pose == "ipad", "Only the iPad destination runs the iPad spot checks")
        launch(); let collection = row("collection-sample-back-rank"); wait(collection)
        XCTAssertTrue(collection.isHittable, "The home list shows in the sidebar\n\(app.debugDescription)")
        collection.tap()
        let browse = button("browse-puzzles"); wait(browse)
        XCTAssertTrue(collection.isHittable, "The sidebar stays beside the collection\n\(app.debugDescription)")
        XCTAssertGreaterThanOrEqual(browse.frame.minX, collection.frame.maxX - 1, "The collection is in the detail column")
        XCTAssertLessThanOrEqual(browse.frame.maxX, app.windows.firstMatch.frame.maxX + 1)
        capture("ipad-split-collection")
    }

    func testIPadAnalysisBoardFitsWithoutScrolling() throws {
        try XCTSkipUnless(pose == "ipad", "Only the iPad destination runs the iPad spot checks")
        launch("game:sample"); wait(square("a1")); wait(square("h8"))
        XCTAssertTrue(square("a1").isHittable); XCTAssertTrue(square("h8").isHittable)
        let window = app.windows.firstMatch.frame, board = boardFrame()
        XCTAssertTrue(window.contains(board), "\(board) runs off \(window)")
        XCTAssertEqual(board.width, board.height, accuracy: 1)
        XCTAssertGreaterThanOrEqual(board.width, 560, "The landscape board uses the height (672 pt at 1194 × 834)")
        let list = app.descendants(matching: .any)["game-move-list"]; wait(list)
        XCTAssertGreaterThanOrEqual(list.frame.minX, board.maxX, "Two panes: the moves sit beside the board")
        for id in ["game-flip-board", "game-previous-move", "game-next-move"] {
            let item = button(id); wait(item)
            XCTAssertFalse(item.frame.intersects(board), "\(id) is a bar item clear of the board")
        }
        tap(button("game-next-move"), until: "label CONTAINS 'Pawn'", on: square("e4"))
        XCTAssertEqual(boardFrame(), board, "Stepping doesn't move the board")
        capture("ipad-analysis")
    }
}
