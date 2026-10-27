import XCTest

@MainActor class FlowTestCase: XCTestCase {
    let app = XCUIApplication()
    func launch(_ route: String? = nil, seeded: Bool = true, offline: Bool = false) {
        continueAfterFailure = false
        app.launchArguments = ["-MotifMemoryBackend", "YES", "-MotifSeedSamples", seeded ? "YES" : "NO"]
        if let route { app.launchArguments += ["-MotifRoute", route] }
        if offline { app.launchArguments += ["-MotifOffline", "YES"] }
        app.launch()
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
