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

    func testEngineLinesShowTheTopThreeAndPlayTheirFirstMove() {
        launch("game-eval"); wait(square("e2")); wait(button("game-engine-lines"))
        let lines = app.descendants(matching: .any)["engine-lines"]
        // The toggle persists, so an earlier run may have left the lines shown.
        if !lines.waitForExistence(timeout: 2) { button("game-engine-lines").tap() }
        wait(lines)
        // The scripted engine's lines are the legal moves in square order: Na3, Nc3, Nf3.
        let best = button("engine-line-0"); wait(best)
        expect(best, "label CONTAINS '1. Na3' AND label CONTAINS 'White better by 0.60'")
        expect(button("engine-line-2"), "label CONTAINS '1. Nf3' AND label CONTAINS 'White better by 0.40'")
        capture("engine-lines")
        best.tap(); expect(square("a3"), "label CONTAINS[c] 'knight'")
        button("game-engine-lines").tap(); expect(lines, "exists == false")
    }

    func testHoldingPreviousAndNextJumpsToTheEnds() {
        launch("game-eval"); wait(square("e2"))
        button("game-next-move").press(forDuration: 1); expect(button("game-next-move"), "isEnabled == false")
        button("game-previous-move").press(forDuration: 1); expect(square("e2"), "label CONTAINS 'Pawn'")
        expect(button("game-previous-move"), "isEnabled == false")
    }

    private func toggle(_ label: String) {
        button("game-actions").tap()
        let item = button("game-toggle-evaluation"); wait(item)
        XCTAssertEqual(item.label, label); item.tap()
    }
}
