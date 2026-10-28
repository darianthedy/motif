import XCTest

@MainActor class FlowTestCase: XCTestCase {
    let app = XCUIApplication()
    /// A loaded CI simulator can stall for a minute reaping the previous test's app, and `launch()` then fails
    /// with "Failed to terminate com.dthedy.Motif:<pid>" before this test has done anything. That one issue is
    /// the simulator's, so it buys a second launch; the app must still come up in the foreground.
    func launch(_ route: String? = nil, seeded: Bool = true, offline: Bool = false, extra: [String] = [], file: StaticString = #filePath, line: UInt = #line) {
        app.launchArguments = ["-MotifMemoryBackend", "YES", "-MotifSeedSamples", seeded ? "YES" : "NO"] + extra
        if let route { app.launchArguments += ["-MotifRoute", route] }
        if offline { app.launchArguments += ["-MotifOffline", "YES"] }
        continueAfterFailure = true
        for _ in 0..<2 {
            let stalled = Flag()
            let options = XCTExpectedFailure.Options()
            options.isStrict = false
            options.issueMatcher = { @Sendable issue in
                guard issue.compactDescription.contains("Failed to terminate com.dthedy.Motif") else { return false }
                stalled.set(); return true
            }
            XCTExpectFailure("The simulator failed to reap the previous app", options: options) { app.launch() }
            if !stalled.isSet { break }
        }
        continueAfterFailure = false
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "Motif never came to the foreground", file: file, line: line)
    }
    func button(_ id: String) -> XCUIElement { app.buttons[id] }
    func square(_ name: String) -> XCUIElement { button("square-" + name) }
    func tap(_ name: String) { XCTAssertTrue(square(name).waitForExistence(timeout: 10)); square(name).tap() }
    /// A loaded CI simulator can drop a tap outright (XCTest reports it sent; the app never sees it). Tap, then
    /// tap again only while `target` provably still doesn't match `format`, so a slow-but-delivered tap isn't doubled.
    /// The proof gets the same 10s as `expect`: a stalled simulator can spend 4s answering one query, and a re-tap
    /// after a move was played hits a board that no longer takes taps.
    func tap(_ element: XCUIElement, until format: String, on target: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        for _ in 0..<3 {
            element.tap()
            if matches(target ?? element, format, timeout: 10) { return }
        }
        XCTFail("\(target ?? element) never matched \(format) after 3 taps", file: file, line: line)
    }
    /// `tap(_:until:on:)` for a long press, which a loaded simulator can drop the same way.
    func hold(_ element: XCUIElement, until format: String, on target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        for _ in 0..<3 {
            element.press(forDuration: 1)
            if matches(target, format, timeout: 10) { return }
        }
        XCTFail("\(target) never matched \(format) after 3 long presses", file: file, line: line)
    }
    /// For state that settles after an action: an immediate check races the UI on a loaded simulator.
    func expect(_ element: XCUIElement, _ format: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(matches(element, format, timeout: 10), "\(element) never matched \(format)\n\(app.debugDescription)", file: file, line: line)
    }
    func matches(_ element: XCUIElement, _ format: String, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)], timeout: timeout) == .completed
    }
    /// Tap-to-move. Selection flips the moment the app sees a tap, so it proves each tap landed: the first
    /// selects `from`, the second clears it whatever the move's outcome (played, rejected, or promotion picker).
    func move(_ from: String, _ to: String) {
        tap(square(from), until: "isSelected == true")
        tap(square(to), until: "isSelected == false", on: square(from))
    }
    /// Missing-piece placement: the tapped empty square stays selected while the picker is up.
    func place(_ name: String) { tap(square(name), until: "isSelected == true") }
    func drag(_ from: String, _ to: String) { XCTAssertTrue(square(from).waitForExistence(timeout: 10)); square(from).press(forDuration: 0.1, thenDragTo: square(to)) }
    func wait(_ element: XCUIElement) { XCTAssertTrue(element.waitForExistence(timeout: 15), app.debugDescription) }
    func dismissKeyboard() { if button("keyboard-done").waitForExistence(timeout: 3) { button("keyboard-done").tap() } }
    func labelButton(_ text: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch }
    func capture(_ name: String) { let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image) }
    func importPuzzle(_ json: String, name: String) {
        let text = app.textViews["puzzle-import-text"]; wait(text); text.tap(); text.typeText(json); dismissKeyboard()
        let add = button("puzzle-import-add"); if !add.isHittable { app.swipeUp() }; wait(add); add.tap()
        let collection = labelButton(name); wait(collection); collection.tap(); wait(button("solve-ordered")); button("solve-ordered").tap()
        wait(square("a1"))
    }
}
/// Set from XCTest's issue matcher, which may run off the main actor.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
