import XCTest

@MainActor final class AccountFlowTests: FlowTestCase {
    func testAvatarOpensAccountAndResetClearsProgress() {
        launch("session:all"); tap("a1"); tap("a8"); wait(app.staticTexts["result-verdict"])
        // The attempt is recorded on Continue, not when the card appears.
        button("result-continue").tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["result-verdict"]); waitForExpectations(timeout: 10)
        button("session-stop").tap(); wait(button("account")); button("account").tap()
        let reset = button("reset-progress"); wait(reset); XCTAssertTrue(reset.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["account-email"].label.contains("sample@motif.local"))
        capture("account")
        reset.tap(); let confirm = app.buttons["Reset Progress"]; wait(confirm); capture("account-reset"); confirm.tap()
        expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: reset); waitForExpectations(timeout: 10)
        button("account-close").tap(); wait(button("import-puzzles"))
    }
    func testSignOutFromAccountSheet() {
        launch("account"); wait(button("sign-out")); button("sign-out").tap(); wait(button("sign-in"))
    }
    func testOfflineAccountDisablesSignOutAndReset() {
        launch("account", offline: true); wait(button("sign-out"))
        XCTAssertFalse(button("sign-out").isEnabled); XCTAssertFalse(button("reset-progress").isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["sync-status"].label.contains("Offline")); capture("account-offline")
    }
}
