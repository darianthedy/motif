import XCTest

/// D08: the one banner rule (decision 22) and the New Game sheet's layout (decision 21).
@MainActor final class SheetsBannersFlowTests: FlowTestCase {
    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    /// Errors and the toast are capsules ≤ 480 pt at the bottom of the content: clear of the
    /// board, the tab bar, the bottom bar and the Previous / Next Move items, wherever the
    /// system puts those (bottom bar on iPhone, side bar on IL).
    func testToastAndErrorSitAtTheBottomClearOfBarsAndBoard() {
        launch("game:sample", extra: ["-MotifFixture", "notice,error"])
        wait(square("a1")); wait(square("h8"))
        let toast = app.buttons.matching(NSPredicate(format: "identifier == 'toast' AND label == 'PGN copied.'")).firstMatch
        let error = any("error-banner")
        wait(toast); wait(error)
        let board = boardFrame()
        let window = app.windows.firstMatch.frame
        var bars = app.tabBars.allElementsBoundByIndex.filter { $0.isHittable }.map { $0.frame }
        bars += app.toolbars.allElementsBoundByIndex.filter { $0.isHittable }.map { $0.frame }
        bars += ["game-previous-move", "game-next-move"].map { button($0) }.filter { $0.isHittable }.map { $0.frame }
        for (name, element) in [("toast", toast), ("error-banner", error)] {
            let frame = element.frame
            XCTAssertLessThanOrEqual(frame.width, 480 + 1, name)
            XCTAssertFalse(frame.intersects(board), "\(name) covers the board\n\(app.debugDescription)")
            XCTAssertGreaterThan(frame.midY, window.midY, "\(name) sits at the bottom of the content")
            for bar in bars { XCTAssertFalse(frame.intersects(bar), "\(name) overlaps a bar at \(bar)\n\(app.debugDescription)") }
        }
        error.buttons["error-dismiss"].tap(); expect(error, "exists == false")
    }
    /// On the Duo opened wide (IL) the New Game sheet is ≥ 600 pt wide, so the preview sits beside
    /// the form: the FEN field and the board side by side, both in view.
    func testOpenWideNewGamePutsThePreviewBesideTheFenField() throws {
        try XCTSkipIf(pose != "IL", "Only the Duo opened wide (IL) has a sheet this wide")
        launch("game-new"); wait(button("game-new-board"))
        app.buttons["From a FEN"].tap()
        let field = any("game-start-fen"), preview = any("game-new-preview")
        wait(field); wait(preview)
        XCTAssertTrue(field.isHittable); XCTAssertTrue(preview.isHittable)
        XCTAssertLessThanOrEqual(preview.frame.maxX, field.frame.minX, "The preview leads the form")
        XCTAssertLessThan(preview.frame.minY, field.frame.maxY, "Side by side, not stacked")
        XCTAssertGreaterThan(preview.frame.maxY, field.frame.minY, "Side by side, not stacked")
        XCTAssertEqual(preview.frame.width, preview.frame.height, accuracy: 1)
    }
    /// Narrower sheets stack the preview, capped at 40 % of the sheet, so the FEN field and its
    /// error are in view without scrolling.
    func testStackedNewGameKeepsTheFenFieldAndErrorInView() throws {
        try XCTSkipIf(pose == "IL", "IL puts the preview beside the form")
        launch("game-new"); wait(button("game-new-board"))
        app.buttons["From a FEN"].tap()
        let field = any("game-start-fen"), preview = any("game-new-preview")
        wait(field); wait(preview)
        XCTAssertTrue(field.isHittable, app.debugDescription)
        XCTAssertGreaterThanOrEqual(field.frame.minY, preview.frame.maxY, "Stacked under the preview")
        XCTAssertLessThanOrEqual(preview.frame.height, app.windows.firstMatch.frame.height * 0.4 + 1)
        type("bad", into: field); dismissKeyboard()
        let error = any("game-fen-error"); wait(error); XCTAssertTrue(error.isHittable, app.debugDescription)
    }
    /// The "needs a connection" note is the first thing in the form (F19).
    func testOfflineNewGameShowsTheNoteAboveTheForm() {
        launch("game-new", offline: true); wait(button("game-new-board"))
        let note = any("game-new-offline"); wait(note); XCTAssertTrue(note.isHittable)
        XCTAssertLessThan(note.frame.maxY, any("game-start-mode").frame.minY + 1)
        expect(button("game-new-board"), "isEnabled == false")
    }
}
