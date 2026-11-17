import XCTest

/// Scan plan S05 and S07: a session through one flagged puzzle with its full scan and one quiet
/// puzzle (the bundled sample's two), undo and skip, and a run played offline, quit, resumed and uploaded on reconnect.
@MainActor final class ScanSessionFlowTests: FlowTestCase {
    func testFlaggedAndQuietPuzzles() {
        launch("scan"); start()
        // The queue is drawn at random: the flagged sample has Black's knight on f6, the quiet one doesn't.
        // The quiet one is failed the first time, so it comes back once more in the run (a retry).
        var quietPlayed = false
        let done = button("session-done")
        for _ in 0..<3 {
            let call = button("scan-flag")
            XCTAssertTrue(matches(call, "exists == true", timeout: 15) || done.exists)
            if done.exists { break }
            if square("f6").label.lowercased().contains("knight") { playFlagged() }
            else { playQuiet(best: quietPlayed); quietPlayed = true }
        }
        wait(done); capture("scan-session-complete")
        done.tap(); wait(button("scan-start")); XCTAssertFalse(button("resume-scan-session").exists)
    }

    func testUndoAndSkip() {
        launch("scan"); start()
        wait(button("scan-flag")); XCTAssertFalse(button("scan-undo").isEnabled)
        tap("a3"); expect(square("a3"), "label ENDSWITH 'marked'")
        let undo = button("scan-undo"); expect(undo, "isEnabled == true"); undo.tap()
        expect(square("a3"), "NOT (label ENDSWITH 'marked')"); expect(undo, "isEnabled == false")
        XCTAssertTrue(shown("Puzzle 1 of 2").exists)
        button("scan-skip").tap()
        wait(shown("Puzzle 2 of 2")); wait(button("scan-flag"))
    }

    func testOfflinePlayQuitResumeAndUploadOnReconnect() {
        let store = "scan-offline-" + UUID().uuidString
        launch("scan", offline: true, extra: ["-MotifFixture", "store=\(store)"])
        wait(shown("Offline")); start()
        let call = button("scan-flag"); wait(call)
        if square("f6").label.lowercased().contains("knight") { playFlagged() } else { playQuiet(best: true) }  // passed, so no retry: puzzle 2 is next
        wait(shown("Puzzle 2 of 2")); wait(button("scan-flag"))
        wait(shown("results waiting")); capture("scan-session-offline")
        // Quit mid-run: the finished puzzle is in the outbox, the open one isn't saved.
        app.terminate()

        launch("scan", extra: ["-MotifFixture", "store=\(store),offline-first,online-after=6"])
        let resume = button("resume-scan-session"); wait(resume)
        wait(shown("results waiting"))
        resume.tap(); wait(shown("Puzzle 2 of 2")); wait(button("scan-flag"))
        // Back online: the run and its attempt upload, and the run still resumes at puzzle 2.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: shown("Offline"))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 30), .completed, "never came back online")
        XCTAssertTrue(shown("Puzzle 2 of 2").exists)
        XCTAssertTrue(button("scan-flag").exists, "the open puzzle stays open through the upload")
    }

    // MARK: Helpers

    private func start() { let start = button("scan-start"); wait(start); start.tap() }

    /// After 3…Nf6: the knight attacks e4. Flag; the full scan's targets (e4 red, e5 and f7
    /// orange, a dot on e7) and arrows (Nxe4 theirs, Ng5 yours); then d3, the best move, taken
    /// back once at the final check and then played.
    private func playFlagged() {
        tap("e4"); expect(square("e4"), "label ENDSWITH 'marked'"); capture("scan-quick-scan")
        button("scan-flag").tap()
        expectFeedback("Clean Scan"); capture("scan-quick-scan-feedback")
        button("scan-continue").tap()
        let next = button("scan-next"); wait(next)
        tap(square("e4"), until: "label ENDSWITH 'loses material'")
        for name in ["e5", "f7"] {
            tap(square(name), until: "label ENDSWITH 'loses material'")
            tap(square(name), until: "label ENDSWITH 'as often as defended'")
        }
        tap(square("e7"), until: "label ENDSWITH 'dot'"); capture("scan-targets")
        next.tap(); expectFeedback("All Targets Found"); capture("scan-targets-feedback")
        button("scan-continue").tap()
        wait(next)
        square("f6").press(forDuration: 0.1, thenDragTo: square("e4")); wait(button("scan-arrow-f6e4"))
        tap(square("f3"), until: "isSelected == true")
        tap(square("g5"), until: "isSelected == false", on: square("f3"))
        wait(button("scan-arrow-f3g5")); capture("scan-arrows")
        next.tap(); expectFeedback("All Arrows Found"); capture("scan-arrows-feedback")
        button("scan-continue").tap()
        // The final check (S08): Take Back, then d3 again and Play It.
        wait(app.descendants(matching: .any)["scan-prompt"]); move("d2", "d3")
        let takeBack = button("scan-take-back"); wait(takeBack)
        expect(square("d3"), "label CONTAINS 'to play here'"); capture("scan-final-check")
        takeBack.tap()
        wait(app.descendants(matching: .any)["scan-prompt"]); move("d2", "d3")
        let playIt = button("scan-play-it"); wait(playIt); playIt.tap()
        expectFeedback("Passed"); capture("scan-move-feedback")
        button("scan-continue").tap()
    }

    /// After 2…Nc6, nothing needs a Flag. No Flag, then Bb5 (best), or Na3, a pawn worse: a fail.
    private func playQuiet(best: Bool = false) {
        button("scan-no-flag").tap()
        expectFeedback("Clean Scan")
        button("scan-continue").tap()
        wait(app.descendants(matching: .any)["scan-prompt"]); if best { move("f1", "b5"); expectFeedback("Passed") }
        else { move("b1", "a3"); expectFeedback("Mistake"); capture("scan-move-mistake") }
        button("scan-continue").tap()
    }

    private func expectFeedback(_ title: String) {
        let feedback = app.descendants(matching: .any)["scan-feedback"]; wait(feedback)
        expect(feedback, "label BEGINSWITH '\(title)'")
    }

    private func shown(_ value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", value, value)).firstMatch
    }
}
