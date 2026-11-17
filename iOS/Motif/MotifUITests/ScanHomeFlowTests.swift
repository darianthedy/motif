import XCTest

/// Scan plan S04: the Scan tab's home, All Puzzles, a puzzle's detail, Start and Discard, import.
@MainActor final class ScanHomeFlowTests: FlowTestCase {
    func testHomeListsThePoolAndOpensAPuzzle() {
        launch("scan"); let all = button("scan-all-puzzles"); wait(all); capture("scan-home")
        XCTAssertTrue(button("scan-start").exists); XCTAssertFalse(button("scan-review-mistakes").isEnabled)
        all.tap(); let row = button("scan-puzzle-sample-scan-0"); wait(row); capture("scan-list")
        row.tap(); wait(app.descendants(matching: .any)["scan-detail-list"])
        // LabeledContent can read as one element ("Last Move, 3... Nf6"), so match on the text inside.
        wait(shown("3... Nf6")); XCTAssertTrue(shown("e4 attacked").exists)
        XCTAssertTrue(square("e4").label.hasSuffix("marked"), square("e4").label); capture("scan-detail")
    }
    private func shown(_ value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", value, value)).firstMatch
    }
    func testStartOpensASessionAndDiscardEndsIt() {
        launch("scan"); let start = button("scan-start"); wait(start); start.tap()
        let done = button("scan-session-done"); wait(done); done.tap()
        let discard = button("discard-scan-session"); wait(discard); XCTAssertFalse(button("scan-start").exists)
        capture("scan-session-in-progress")
        discard.tap(); wait(button("scan-start"))
    }
    func testImportAddsToThePool() {
        launch("scan-import"); let add = button("scan-import-add"); wait(add); XCTAssertFalse(add.isEnabled)
        let text = app.textViews["scan-import-text"]; text.tap()
        text.typeText(#"{"version":1,"scan":[{"fenBefore":"4k3/8/8/8/8/8/8/4K3 w - - 0 1","lastMove":"e1d1","flagged":false,"quickScan":[],"moves":{"e8d8":0,"e8d7":0,"e8e7":0,"e8f7":0,"e8f8":0}},{"fenBefore":"bad"}]}"#)
        dismissKeyboard(); wait(shown("1 puzzle rejected")); expect(add, "isEnabled == true"); capture("scan-import")
        add.tap(); wait(button("scan-all-puzzles")); XCTAssertTrue(shown("3").exists)
    }
    func testOfflineDisablesImport() {
        launch("scan", offline: true); wait(app.descendants(matching: .any)["offline-banner"])
        button("scan-actions").tap()
        expect(app.buttons["Import Scan Puzzles…"], "isEnabled == false")
    }
}
