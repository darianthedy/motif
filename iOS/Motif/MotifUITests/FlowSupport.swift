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
