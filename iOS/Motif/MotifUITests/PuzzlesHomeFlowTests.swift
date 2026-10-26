import XCTest

@MainActor final class PuzzlesHomeFlowTests: FlowTestCase {
    func testRowMenuRenamesAndSwipeDeletesACollection() {
        launch(); let row = button("collection-sample-back-rank"); wait(row); capture("puzzles-home")
        row.press(forDuration: 1.2); let rename = labelButton("Rename"); wait(rename); rename.tap()
        let field = app.alerts.textFields.firstMatch; wait(field); field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 60) + "Renamed set")
        app.alerts.buttons["Save"].tap(); wait(labelButton("Renamed set"))

        let doomed = button("collection-sample-missing-piece"); wait(doomed); doomed.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch; wait(delete); delete.tap()
        // The dialog's action can appear more than once in the tree; tap the one on screen.
        let confirms = app.buttons.matching(NSPredicate(format: "label == %@", "Delete Collection")); wait(confirms.firstMatch)
        let confirm = confirms.allElementsBoundByIndex.first(where: \.isHittable); XCTAssertNotNil(confirm, app.debugDescription); confirm?.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: doomed); waitForExpectations(timeout: 10)
        XCTAssertTrue(button("collection-sample-back-rank").exists)
    }
    func testOfflineDisablesImportAndShowsThePill() {
        launch(offline: true); wait(button("import-puzzles"))
        XCTAssertFalse(button("import-puzzles").isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["offline-banner"].exists); capture("puzzles-offline")
    }
    func testImportSheetConfirmsFromTheToolbar() {
        launch("import"); let add = button("puzzle-import-add"); wait(add); XCTAssertFalse(add.isEnabled)
        let text = app.textViews["puzzle-import-text"]; text.tap()
        text.typeText(#"{"collection":"Toolbar","puzzles":[{"fen":"6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1","solutions":[["a1a8"]]},{"fen":"bad"}]}"#); dismissKeyboard()
        wait(app.staticTexts["1 row rejected"]); XCTAssertTrue(add.isEnabled); capture("import-errors")
        add.tap(); wait(labelButton("Toolbar"))
    }
}
