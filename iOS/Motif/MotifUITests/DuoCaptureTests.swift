import XCTest

/// iPhone Duo Phase 2: every state in the plan's §4 inventory, captured as one
/// screenshot named for its cell (`S15c`, `S17a-S04`). Skipped unless the runner
/// sets `MOTIF_CAPTURE=1` (`TEST_RUNNER_MOTIF_CAPTURE=1` through xcodebuild), so the
/// PR check doesn't pay for it. `scripts/ios-duo-capture.sh` sets the pose, runs this,
/// and exports the screenshots.
///
/// `MOTIF_CAPTURE_ONLY` narrows a run: comma-separated id prefixes (`S08,S15`), and
/// `primary` for every screen's first state. Each state launches fresh; a state that
/// can't be reached records a failure and is still captured, so the grid shows it.
@MainActor final class DuoCaptureTests: FlowTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(environment["MOTIF_CAPTURE"] == "1", "Set MOTIF_CAPTURE=1 to capture the iPhone Duo states")
        XCUIDevice.shared.appearance = .light
    }
    private func wanted(_ id: String) -> Bool {
        guard let only = environment["MOTIF_CAPTURE_ONLY"], !only.isEmpty else { return true }
        let state = id.split(separator: "-").first.map(String.init) ?? id
        return only.split(separator: ",").contains { token in
            token == "primary" ? state.hasSuffix("a") : id.hasPrefix(token)
        }
    }
    /// Launch on `route` with `fixture`, run `reach`, let the UI settle, and save the screen.
    /// A state whose `reach` loses an element relaunches once, and is still captured after a
    /// second miss: the miss goes in `<dir>/unreached.txt` so the grid can mark the cell.
    private func shot(_ id: String, _ route: String? = nil, fixture: String = "", seeded: Bool = true, offline: Bool = false,
                      settle: TimeInterval = 1.2, _ reach: () -> Void = {}) {
        guard wanted(id) else { return }
        XCTContext.runActivity(named: id) { _ in
            for attempt in 1...2 {
                missing = nil
                // `capture` always sets a fixture, so the Analysis view's toggles reset each launch.
                launch(route, seeded: seeded, offline: offline, extra: ["-MotifFixture", fixture.isEmpty ? "capture" : "capture," + fixture])
                continueAfterFailure = true
                reach()
                if missing == nil || attempt == 2 { break }
            }
            Thread.sleep(forTimeInterval: settle)
            save(id)
            if let missing {
                XCTFail("\(id) not reached: \(missing)")
                note("unreached.txt", "\(id)\t\(missing)\n")
            }
        }
    }
    private func note(_ file: String, _ line: String) {
        guard let dir = environment["MOTIF_CAPTURE_DIR"], !dir.isEmpty else { return }
        let path = dir + "/" + file
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
    }
    /// XCUIScreen only sees the cover screen, so with `MOTIF_CAPTURE_DIR` set the host script
    /// takes the shot with duoctl, which captures whichever screen is showing: this asks
    /// through `<dir>/request` and waits for `<dir>/<id>.png`.
    private func save(_ id: String) {
        if let dir = environment["MOTIF_CAPTURE_DIR"], !dir.isEmpty {
            let files = FileManager.default, shot = dir + "/" + id + ".png"
            try? files.removeItem(atPath: shot)
            for _ in 0..<2 {
                try? id.write(toFile: dir + "/request", atomically: true, encoding: .utf8)
                let deadline = Date().addingTimeInterval(30)
                while !files.fileExists(atPath: shot), Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
                if files.fileExists(atPath: shot) { return }
            }
            XCTFail("The host didn't capture \(id)")
        }
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = id; image.lifetime = .keepAlways; add(image)
    }

    /// The first element a state's `reach` couldn't find. Once set, the remaining steps are
    /// skipped: XCTest stops the whole test when it taps an element that isn't there.
    private var missing: String?
    private func present(_ element: XCUIElement, _ timeout: TimeInterval = 10) -> Bool {
        guard missing == nil else { return false }
        if element.waitForExistence(timeout: timeout) { return true }
        missing = element.description; return false
    }
    override func wait(_ element: XCUIElement) { _ = present(element, 15) }
    override func move(_ from: String, _ to: String) { guard present(square(from)), present(square(to)) else { return }; super.move(from, to) }
    override func place(_ name: String) { guard present(square(name)) else { return }; super.place(name) }
    /// Toolbar items in the side bar, and menu items, can lose their identifier; their
    /// titles find them there.
    private static let titles = [
        "account-close": "Close", "game-select-done": "Done", "game-bulk-move": "Move", "game-bulk-delete": "Delete",
        "save-game-confirm": "Save Game", "game-new-board": "Create Game", "puzzle-import-add": "Add 2 Puzzles",
        "game-import-add": "Add 2 Games", "game-back": "Back", "game-save-as-game": "Save as Game…",
        "game-export-pgn": "Export PGN…", "game-select": "Select Games", "game-select-all": "Select All",
        "add-games": "Add Games", "game-collection-actions": "More", "collection-actions": "More",
        "puzzle-actions": "Puzzle actions", "game-actions": "Game actions", "result-analyze": "Analyze",
        "session-skip": "Skip", "session-flag": "Flag", "session-stop": "End Session", "reset-progress": "Reset Puzzle Progress…",
        "new-game-collection": "New Collection", "import-puzzles": "Import Puzzles", "puzzle-next-move": "Next move",
        "game-next-move": "Next move", "puzzle-detail-comment": "Comment", "puzzle-import-paste": "Paste From Clipboard",
        "game-import-paste": "Paste From Clipboard", "load-sign-out": "Sign Out", "sign-in": "Sign In",
    ]
    override func button(_ id: String) -> XCUIElement {
        guard let title = Self.titles[id] else { return super.button(id) }
        return app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, title)).firstMatch
    }
    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func tapIf(_ element: XCUIElement) { if present(element) { element.tap() } }
    private func tapButton(_ id: String) { tapIf(button(id)) }
    /// A menu, dialog or alert item, found by its title.
    private func item(_ title: String) {
        // A menu picker's label also carries its value ("Collection, New Collection").
        let matches = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title + ","))
        guard present(matches.firstMatch) else { return }
        (matches.allElementsBoundByIndex.first(where: \.isHittable) ?? matches.firstMatch).tap()
    }
    private func type(into element: XCUIElement, _ text: String) { if present(element) { element.tap(); element.typeText(text) } }
    /// With bars in the side bar, the search field can sit behind a Search button.
    private func search(_ text: String) {
        let field = app.searchFields.firstMatch
        if missing == nil, !field.waitForExistence(timeout: 4) { tapIf(app.buttons["Search"]) }
        guard present(field) else { return }
        field.tap(); if !text.isEmpty { field.typeText(text) }
    }
    private func swipeRow(_ id: String) { let row = any(id); if present(row) { row.swipeLeft() } }
    private func pressRow(_ id: String) { let row = any(id); if present(row) { row.press(forDuration: 1.2) } }
    private func hold(_ element: XCUIElement, _ seconds: TimeInterval = 1.2) { if present(element) { element.press(forDuration: seconds) } }
    private func next(_ times: Int = 1) { for _ in 0..<times { tapButton("game-next-move"); Thread.sleep(forTimeInterval: 0.3) } }
    private func fillSignIn() {
        type(into: app.textFields["auth-email"], "solver@example.test\n")
        type(into: app.secureTextFields["auth-password"], "anything\n")
    }

    func testS01Launch() {
        shot("S01a", fixture: "hang-user")
        shot("S01b", fixture: "hang-load") { wait(any("load-progress")) }
        shot("S01c", fixture: "offline-first") { wait(any("load-offline")) }
        shot("S01d", fixture: "fail-load") { wait(button("load-retry")) }
        shot("S01e", fixture: "fail-load,fail-signout") { tapButton("load-sign-out"); wait(any("error-banner")) }
    }
    func testS02SignIn() {
        shot("S02a", "signin", fixture: "prod-account") { wait(app.textFields["auth-email"]) }
        shot("S02b", "signin", fixture: "prod-account") { fillSignIn() }
        shot("S02c", "signin", fixture: "prod-account") { tapIf(app.textFields["auth-email"]) }
        shot("S02d", "signin", fixture: "prod-account,hang-signin") { fillSignIn(); tapButton("sign-in") }
        shot("S02e", "signin", fixture: "prod-account,fail-signin") { fillSignIn(); tapButton("sign-in"); wait(any("sign-in-error")) }
        shot("S02f", "signin", fixture: "prod-account", offline: true) { wait(any("offline-banner")) }
        shot("S02g", "signin") { wait(app.textFields["auth-email"]) }
    }
    func testS03Account() {
        let ready = { self.wait(self.button("account-close")) }
        shot("S03a", "account", fixture: "seed=progress,prod-account", ready)
        shot("S03b", "account", fixture: "status=syncing,prod-account", ready)
        shot("S03c", "account", fixture: "pending=3,prod-account", ready)
        shot("S03d", "account", fixture: "prod-account", offline: true, ready)
        shot("S03e", "account", fixture: "pending=2,prod-account", offline: true, ready)
        shot("S03f", "account", fixture: "status=error,prod-account", ready)
        shot("S03g", "account", fixture: "prod-account", ready)
        shot("S03h", "account", fixture: "seed=progress,prod-account") { tapButton("reset-progress"); wait(button("reset-confirm")) }
        shot("S03i", "account") { ready(); app.swipeUp() }
        shot("S03j", "account", fixture: "seed=progress,prod-account", settle: 0.3) { tapButton("reset-progress"); item("Reset Progress"); wait(any("toast")) }
        shot("S03k", "account", fixture: "error,prod-account") { wait(any("error-banner")) }
    }
    func testS04PuzzlesHome() {
        let row = "collection-sample-back-rank"
        shot("S04a", fixture: "seed=progress") { wait(button("resume-random")) }
        shot("S04b") { wait(any(row)) }
        shot("S04c", fixture: "seed=collections") { wait(any(row)) }
        shot("S04d", fixture: "seed=empty") { wait(app.staticTexts["No Puzzles Yet"]) }
        shot("S04e", fixture: "seed=empty", offline: true) { wait(app.staticTexts["No Puzzles Yet"]) }
        shot("S04f", offline: true) { wait(any(row)) }
        shot("S04g") { pressRow(row) }
        shot("S04h") { swipeRow(row) }
        shot("S04i") { pressRow(row); item("Rename…"); wait(app.alerts.firstMatch) }
        shot("S04j") { swipeRow(row); item("Delete"); wait(app.buttons["Delete Collection"]) }
    }
    func testS05ImportPuzzles() {
        let ready = { self.wait(self.app.textViews["puzzle-import-text"]) }
        shot("S05a", "import", ready)
        shot("S05b", "import", fixture: "import=valid") { ready(); item("Collection"); item("Back-rank mates") }
        shot("S05c", "import", fixture: "import=new", ready)
        shot("S05d", "import", fixture: "import=rejects", ready)
        shot("S05e", "import", fixture: "import=all-rejected", ready)
        shot("S05f", "import", fixture: "import=multi", ready)
        shot("S05g", "import") { tapButton("puzzle-import-paste"); wait(any("puzzle-import-source-error")) }
        shot("S05h", "import", fixture: "import=new,hang-writes") { tapButton("puzzle-import-add") }
        shot("S05i", "import", fixture: "import=new", offline: true, ready)
        shot("S05j", "import") { ready(); tapIf(app.textViews["puzzle-import-text"]) }
        shot("S05k", "import", settle: 2.5) { ready(); item("Choose File…") }
    }
    func testS06Collection() {
        let ready = { self.wait(self.button("solve-ordered")) }
        shot("S06a", "collection", ready)
        shot("S06b", "collection", fixture: "seed=progress") { wait(button("resume-session")) }
        shot("S06c", "collection") { tapButton("collection-actions") }
        shot("S06d", "collection", fixture: "seed=collections") { wait(app.staticTexts["No Puzzles"]) }
        shot("S06e", "collection") { tapButton("collection-actions"); item("Rename…"); wait(app.alerts.firstMatch) }
        shot("S06f", "collection") { tapButton("collection-actions"); item("Delete Collection"); wait(app.staticTexts["Delete this collection and its puzzles?"]) }
        shot("S06g", "collection", offline: true, ready)
    }
    func testS07PuzzleList() {
        let row = "puzzle-sample-back-rank-0"
        shot("S07a", "puzzle-list") { wait(any(row)) }
        shot("S07b", "puzzle-list") { search("back") }
        shot("S07c", "puzzle-list", fixture: "seed=progress") { search(""); item("Solved") }
        shot("S07d", "puzzle-list-empty") { wait(app.staticTexts["No Flagged Puzzles"]) }
        shot("S07e", "puzzle-list") { search("zzz") }
        shot("S07f", "puzzle-list", fixture: "seed=collections") { wait(app.staticTexts["No Puzzles"]) }
        shot("S07g", "puzzle-list") { swipeRow(row) }
        shot("S07h", "puzzle-list") { swipeRow(row); item("Delete"); wait(app.buttons["Delete Puzzle"]) }
        shot("S07i", "puzzle-list", offline: true) { wait(any(row)) }
    }
    func testS08PuzzleDetail() {
        let ready = { self.wait(self.button("puzzle-actions")) }
        shot("S08a", "puzzle-detail", ready)
        shot("S08b", "puzzle-detail:sample-back-rank-1") { tapButton("puzzle-next-move") }
        shot("S08c", "puzzle-detail:sample-back-rank-2", ready)
        shot("S08d", "puzzle-detail:sample-missing-piece-0", ready)
        shot("S08e", "puzzle-detail:sample-back-rank-2", fixture: "seed=progress", ready)
        shot("S08f", "puzzle-detail") { tapButton("puzzle-actions") }
        shot("S08g", "puzzle-detail") { ready(); app.swipeUp(); tapButton("puzzle-detail-comment"); wait(app.navigationBars["Comment"]) }
        shot("S08h", "puzzle-detail") { tapButton("puzzle-actions"); item("Delete Puzzle"); wait(app.staticTexts["Delete this puzzle from the library?"]) }
        shot("S08i", "puzzle-detail", offline: true, ready)
    }
    func testS09Session() {
        let solve = "session:sample-solve"
        shot("S09a", "session:all") { wait(square("a1")) }
        shot("S09b", "session:all", settle: 0.2) { move("a1", "a7") }
        shot("S09c", "session:all") { for wrong in ["a7", "a6", "a5"] { move("a1", wrong) }; wait(app.staticTexts["Not quite. Play the highlighted move."]) }
        shot("S09d", solve, fixture: "seed=solve,slow-reply", settle: 0.5) { move("d1", "d8"); wait(app.staticTexts["Opponent is replying…"]) }
        shot("S09e", solve, fixture: "seed=solve") { tapButton("session-skip"); move("e7", "e8"); wait(button("choose-q")) }
        shot("S09f", "session:missing") { wait(square("g6")) }
        shot("S09g", "session:missing") { place("g6"); wait(button("choose-n")) }
        shot("S09h", "session:missing") {
            for piece in ["q", "r", "b"] { place("g6"); tapButton("choose-" + piece); Thread.sleep(forTimeInterval: 0.6) }
        }
        shot("S09i", "result:all") { wait(app.staticTexts["result-verdict"]) }
        shot("S09j", "session:all") { tapButton("session-skip"); Thread.sleep(forTimeInterval: 0.8); tapButton("session-skip"); move("b1", "b8"); wait(app.staticTexts["result-verdict"]) }
        shot("S09k", "result:failed") { wait(app.staticTexts["result-verdict"]) }
        shot("S09l", solve, fixture: "seed=solve") {
            tapButton("session-skip"); Thread.sleep(forTimeInterval: 0.8); tapButton("session-skip"); move("a1", "a8"); wait(app.staticTexts["result-verdict"])
        }
        shot("S09m", solve, fixture: "seed=solve") {
            for _ in 0..<3 { tapButton("session-skip"); Thread.sleep(forTimeInterval: 0.8) }; wait(app.staticTexts["Session Complete"])
        }
        shot("S09n", "session:all") { tapButton("session-flag") }
        shot("S09o", "session:all", offline: true) { wait(square("a1")) }
    }
    func testS10PuzzleAnalysis() {
        let open = { self.tapButton("result-analyze"); self.wait(self.button("game-next-move")) }
        shot("S10a", "result:all") { open(); next() }
        shot("S10b", "result:sample-missing-piece") { open() }
        shot("S10c", "result:all") { open(); tapButton("game-actions") }
        shot("S10d", "result:all") { open(); tapButton("game-actions"); tapButton("game-save-as-game"); wait(button("save-game-confirm")) }
        shot("S10e", "result:all") {
            open(); tapButton("game-actions"); tapButton("game-save-as-game"); wait(button("save-game-confirm"))
            tapButton("save-game-collection"); item("New Collection")
        }
        shot("S10f", "result:all", offline: true) { open() }
    }
    func testS11GamesHome() {
        let row = "game-collection-sample-games"
        shot("S11a", "games", fixture: "seed=games") { wait(any(row)) }
        shot("S11b", "games", fixture: "seed=empty") { wait(app.staticTexts["No Games Yet"]) }
        shot("S11c", "games", fixture: "seed=empty", offline: true) { wait(app.staticTexts["No Games Yet"]) }
        shot("S11d", "games") { tapButton("new-game-collection"); wait(app.alerts.firstMatch) }
        shot("S11e", "games") { pressRow(row) }
        shot("S11f", "games") { swipeRow(row) }
        shot("S11g", "games") { pressRow(row); item("Rename…"); wait(app.alerts.firstMatch) }
        shot("S11h", "games") { swipeRow(row); item("Delete"); wait(app.buttons["Delete Collection"]) }
        shot("S11i", "games", offline: true) { wait(any(row)) }
    }
    func testS12GameCollection() {
        let games = "seed=games", ready = { self.wait(self.any("game-row-sample-game")) }
        let select = { self.tapButton("game-collection-actions"); self.tapButton("game-select"); self.wait(self.button("game-select-done")) }
        shot("S12a", "game-collection", fixture: games, ready)
        shot("S12b", "game-collection", fixture: games) { search("zzz") }
        shot("S12c", "game-collection", fixture: games) { tapButton("add-games") }
        shot("S12d", "game-collection", fixture: games) { tapButton("game-collection-actions") }
        shot("S12e", "game-collection", fixture: games) { select() }
        shot("S12f", "game-select", fixture: games) { wait(button("game-bulk-move")) }
        shot("S12g", "game-collection", fixture: games) { select(); tapButton("game-select-all") }
        // A reorder drag can't be held mid-gesture from XCTest; the edit-mode handles are what it starts from.
        shot("S12h", "game-collection", fixture: games) { select(); app.swipeDown() }
        shot("S12i", "game-select", fixture: games) { tapButton("game-bulk-move"); wait(app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH 'Move'")).firstMatch) }
        shot("S12j", "game-collection", fixture: games) { tapButton("game-collection-actions"); item("Rename…"); wait(app.alerts.firstMatch) }
        shot("S12k", "game-collection", fixture: games) { tapButton("game-collection-actions"); item("Delete Collection"); wait(app.staticTexts["Delete this collection and its games?"]) }
        shot("S12l", "game-select", fixture: games) { tapButton("game-bulk-delete"); wait(app.staticTexts["Delete the selected games?"]) }
        shot("S12m", "game-collection", fixture: "seed=collections") { wait(app.staticTexts["No Games"]) }
        shot("S12n", "game-collection", fixture: "seed=collections", offline: true) { wait(app.staticTexts["No Games"]) }
        shot("S12o", "game-collection", fixture: games, offline: true, ready)
        shot("S12p", "game-select", fixture: games, offline: true) { wait(button("game-bulk-move")) }
        shot("S12q", "game-collection", fixture: games, settle: 2.5) { tapButton("game-collection-actions"); item("Export as PGN") }
    }
    func testS13ImportPGN() {
        let ready = { self.wait(self.app.textViews["game-import-text"]) }
        shot("S13a", "game-add", ready)
        shot("S13b", "game-add", fixture: "import=pgn", ready)
        shot("S13c", "game-add", fixture: "import=pgn-many", ready)
        shot("S13d", "game-add", fixture: "import=pgn-errors", ready)
        shot("S13e", "game-add") { tapButton("game-import-paste"); wait(any("game-import-source-error")) }
        shot("S13f", "game-add", fixture: "import=pgn,hang-writes") { tapButton("game-import-add") }
        shot("S13g", "game-add", fixture: "import=pgn", offline: true, ready)
        shot("S13h", "game-add") { ready(); tapIf(app.textViews["game-import-text"]) }
        shot("S13i", "game-add", settle: 2.5) { ready(); item("Choose Files…") }
    }
    func testS14NewGame() {
        let ready = { self.wait(self.button("game-new-board")) }
        let fen = { ready(); self.item("From a FEN") }
        shot("S14a", "game-new", ready)
        shot("S14b", "game-new") { fen() }
        shot("S14c", "game-new") { fen(); type(into: any("game-start-fen"), "7k/4P3/8/8/8/8/8/6K1 w - - 0 1"); dismissKeyboard() }
        shot("S14d", "game-new") { fen(); type(into: any("game-start-fen"), "bad"); dismissKeyboard(); wait(any("game-fen-error")) }
        shot("S14e", "game-new") { fen(); tapIf(any("game-start-fen")) }
        shot("S14f", "game-new", offline: true, ready)
    }
    func testS15Analysis() {
        let game = "game:sample-game", rich = "seed=games,engine"
        let ready = { self.wait(self.square("e2")) }
        shot("S15a", game, fixture: rich, ready)
        shot("S15b", game, fixture: rich + ",eval-off", ready)
        shot("S15c", game, fixture: rich + ",lines") { ready(); wait(any("engine-line-0")) }
        shot("S15d", game, fixture: "seed=games,lines", ready)
        shot("S15e", game, fixture: rich) { next(); wait(button("game-comment")) }
        shot("S15f", game, fixture: rich) { next(3); wait(button("alternative-1")) }
        shot("S15g", game, fixture: rich) { next(); tapButton("alternatives-toggle") }
        shot("S15h", "game-variation", fixture: rich, ready)
        shot("S15i", "game:sample-empty", fixture: rich, ready)
        shot("S15j", game, fixture: rich) { let step = button("game-next-move"); wait(step); hold(step, 1) }
        shot("S15k", "game:sample-promotion", fixture: rich) { move("e7", "e8"); wait(button("choose-q")) }
        shot("S15l", game, fixture: rich) { next(); hold(button("move-0")); wait(app.buttons["Delete From Here"]) }
        shot("S15m", game, fixture: rich) { next(); hold(button("move-0")); item("Delete From Here"); wait(app.staticTexts["Delete this move and every move after it?"]) }
        shot("S15n", game, fixture: rich) { tapButton("game-actions") }
        shot("S15o", game, fixture: rich) { tapButton("game-actions"); item("Delete Game"); wait(app.staticTexts["Delete this game?"]) }
        shot("S15p", game, fixture: rich) { move("c2", "c4"); tapButton("game-back"); wait(app.alerts.firstMatch) }
        shot("S15q", game, fixture: rich, offline: true) { move("c2", "c4"); tapButton("game-back"); wait(app.alerts.firstMatch) }
        shot("S15r", game, fixture: rich, offline: true, ready)
        shot("S15s", game, fixture: rich + ",problem", ready)
        shot("S15t", "game-unreadable") { wait(app.staticTexts["Can't Read This Game"]) }
        shot("S15u", "game-unreadable", offline: true) { wait(app.staticTexts["Can't Read This Game"]) }
        shot("S15v", game, fixture: rich + ",lines") { next(); wait(button("game-comment")); wait(any("engine-line-0")) }
    }
    func testS16AnalysisSheets() {
        let comment = { self.wait(self.app.navigationBars["Comment"]) }
        shot("S16a", "game-comment", comment)
        shot("S16b", "game-comment", fixture: "seed=games") { comment(); wait(app.buttons["Remove Comment"]) }
        shot("S16c", "game-comment") { comment(); if present(app.navigationBars["Comment"]) { app.navigationBars["Comment"].swipeUp() } }
        shot("S16d", "game-comment") { comment(); tapIf(app.textViews["game-comment-text"]) }
        shot("S16e", "game-details") { wait(app.navigationBars["Details"]) }
        shot("S16f", "game-details") { wait(app.navigationBars["Details"]); tapIf(any("game-header-White")) }
        shot("S16g", "game:sample", settle: 2.5) { tapButton("game-actions"); tapButton("game-export-pgn") }
    }
    /// The banners on three hosts: a list, the session and the Analysis view.
    func testS17Banners() {
        let hosts: [(String, String?, () -> Void)] = [
            ("S04", nil, { self.wait(self.any("collection-sample-back-rank")) }),
            ("S09", "session:all", { self.wait(self.square("a1")) }),
            ("S15", "game:sample", { self.wait(self.square("e2")) }),
        ]
        for (host, route, ready) in hosts {
            shot("S17a-" + host, route, offline: true, ready)
            shot("S17b-" + host, route, fixture: "pending=2", offline: true, ready)
            shot("S17c-" + host, route, fixture: "status=error", ready)
            shot("S17d-" + host, route, fixture: "error", ready)
            shot("S17e-" + host, route, fixture: "notice", ready)
        }
    }
}
