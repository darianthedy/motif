import XCTest

@MainActor class FlowTestCase: XCTestCase {
    let app = XCUIApplication()
    /// The destination ios-ci runs on (`iphone`, `IL`, `ipad`; empty elsewhere), from `MOTIF_POSE`, for UI tests
    /// that only hold in one pose: `try XCTSkipIf(pose == "IL", "…")`.
    var pose: String { ProcessInfo.processInfo.environment["MOTIF_POSE"] ?? "" }
    /// Destinations whose window is regular width with both split view columns (IL, iPad in landscape), for
    /// tests of the compact, one-stack layout: `try XCTSkipIf(twoColumns, "…")`.
    var twoColumns: Bool { pose == "IL" || pose == "ipad" }
    /// A loaded CI simulator can stall for a minute reaping the previous test's app, and `launch()` then fails
    /// with "Failed to terminate com.dthedy.Motif:<pid>" before this test has done anything. That one issue is
    /// the simulator's, so it buys a second launch; the app must still come up in the foreground.
    func launch(_ route: String? = nil, seeded: Bool = true, offline: Bool = false, extra: [String] = [], file: StaticString = #filePath, line: UInt = #line) {
        app.launchArguments = ["-MotifMemoryBackend", "YES", "-MotifSeedSamples", seeded ? "YES" : "NO",
                               "-MotifUITestNoAnimations", "YES"] + extra
        if let route { app.launchArguments += ["-MotifRoute", route] }
        if offline { app.launchArguments += ["-MotifOffline", "YES"] }
        // ios-ci's iPad destination runs in landscape (§9 D11); simctl can't turn a simulator, so the test does.
        if pose == "ipad", XCUIDevice.shared.orientation != .landscapeLeft { XCUIDevice.shared.orientation = .landscapeLeft }
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
    func button(_ id: String) -> XCUIElement {
        if let title = Self.toolbarTitles[id] { return button(id, title: title) }
        if let titles = Self.menuTitles[id] {
            return app.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", id, titles)).firstMatch
        }
        return app.buttons[id]
    }
    /// Items of a ⋯ menu (`motifOverflowMenu`), which on iOS 27.1 is the system overflow menu: there
    /// every item loses its identifier, in a `Section` or not, so its title (any it can have) finds it.
    static let menuTitles = [
        "game-save": ["Save"],
        "game-edit-comment": ["Add Comment", "Edit Comment", "Add Game Note", "Edit Game Note"],
        "game-toggle-evaluation": ["Hide Evaluation", "Show Evaluation"],
    ]
    /// Toolbar items that lose their identifier in the side bar (§8.3), found by title there too.
    static let toolbarTitles = [
        "game-flip-board": "Flip Board", "game-engine-lines": "Engine Lines",
        "game-previous-move": "Previous Move", "game-next-move": "Next Move",
        "session-skip": "Skip", "session-stop": "End Session",
        "puzzle-go-to-start": "Go to Start", "puzzle-previous-move": "Previous Move",
        "puzzle-next-move": "Next Move", "puzzle-go-to-end": "Go to End",
    ]
    /// Since the iOS 27 SDK, menu items inside a `Section` (and toolbar items in the side bar) can lose their
    /// identifier, so the item's title finds it too.
    func button(_ id: String, title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, title)).firstMatch
    }
    /// A screen's ⋯ menu (`motifOverflowMenu`): before iOS 27.1 a `Menu` with `id`; on 27.1 the system
    /// overflow button, which carries neither the identifier nor the fallback's title.
    func overflow(_ id: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, FlowTestCase.overflowLabel)).firstMatch
    }
    /// The system overflow button's accessibility label on iOS 27.1.
    static let overflowLabel = "More"
    /// Tap a text field or view, again while the tap left no keyboard focus in it (the New Game sheet's FEN field,
    /// on the iOS 27 runtime), then type. The focus may sit on the element or a descendant, as `typeText` checks.
    func type(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        let inside = field.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        for _ in 0..<3 {
            field.tap()
            if matches(field, "hasKeyboardFocus == true", timeout: 5) || inside.exists { field.typeText(text); return }
        }
        XCTFail("\(field) never took keyboard focus after 3 taps\n\(app.debugDescription)", file: file, line: line)
    }
    func square(_ name: String) -> XCUIElement { button("square-" + name) }
    /// The board's frame, from its corner squares (either orientation).
    func boardFrame() -> CGRect { square("a1").frame.union(square("h8").frame) }
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
    /// `expect` for a button whose label settles after it appears, checked inside the query: one remote
    /// snapshot per poll. A predicate on the element itself resolves it again for each attribute, and on a
    /// loaded simulator one resolution of the game screen took 4–5 s, so no check finished in 10 s.
    func expectButton(_ id: String, _ format: String, file: StaticString = #filePath, line: UInt = #line) {
        let match = app.buttons.matching(NSPredicate(format: "identifier == %@", id)).matching(NSPredicate(format: format)).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 20), "\(id) never matched \(format)\n\(app.debugDescription)", file: file, line: line)
    }
    /// Launch arguments that start the Analysis view's persisted toggles from their defaults (bar shown,
    /// lines hidden), for tests that read the move list: on a short column the lines replace it.
    static let analysisDefaults = ["-MotifFixture", "defaults"]
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
    /// Waits for `element`, then until its frame holds still for a second. On the iPad the puzzle list
    /// slides up about 70 pt after it appears (its search field settling into the navigation bar), so a
    /// tap or swipe right after `wait` landed on the next row or on nothing.
    func settle(_ element: XCUIElement) {
        wait(element)
        var last = element.frame, still = 0
        for _ in 0..<30 where still < 3 {
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 0.35)
            let now = element.frame
            still = now == last ? still + 1 : 0
            last = now
        }
    }
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
