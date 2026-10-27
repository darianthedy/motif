import XCTest

/// The evaluation bar on the `game-eval` route, whose scripted engine reaches depth 22 at
/// +0.6 from the start position and a tenth of a pawn more for every ply.
@MainActor final class EvalBarFlowTests: FlowTestCase {
    var bar: XCUIElement { app.descendants(matching: .any)["eval-bar"] }

    func testBarFollowsThePositionAndHidesAcrossLaunches() {
        XCUIDevice.shared.appearance = .light
        defer { XCUIDevice.shared.appearance = .light }
        launch("game-eval"); wait(square("e2"))
        // The toggle persists, so an earlier run may have left the bar hidden.
        if !bar.waitForExistence(timeout: 5) { toggle("Show Evaluation") }
        wait(bar); XCTAssertEqual(bar.label, "Evaluation")
        expect(bar, "value == 'White is better by 0.6, depth 22'")
        XCTAssertLessThanOrEqual(bar.frame.maxX, square("a1").frame.minX)
        XCTAssertEqual(bar.frame.height, square("a1").frame.height * 8, accuracy: 2)
        capture("eval-bar-light")
        XCUIDevice.shared.appearance = .dark
        expect(bar, "value == 'White is better by 0.6, depth 22'"); capture("eval-bar-dark")
        XCUIDevice.shared.appearance = .light

        let beside = square("a1").frame.width
        tap(button("game-next-move"), until: "value == 'White is better by 0.7, depth 22'", on: bar)

        toggle("Hide Evaluation"); expect(bar, "exists == false")
        XCTAssertGreaterThanOrEqual(square("a1").frame.width, beside, "The hidden bar gives the board its width back")

        launch("game-eval"); wait(square("e2")); wait(button("game-actions"))
        XCTAssertFalse(bar.waitForExistence(timeout: 3), "Hide Evaluation lasts across launches")
        toggle("Show Evaluation"); wait(bar); expect(bar, "value == 'White is better by 0.6, depth 22'")
    }

    private func toggle(_ label: String) {
        button("game-actions").tap()
        let item = button("game-toggle-evaluation"); wait(item)
        XCTAssertEqual(item.label, label); item.tap()
    }
}
