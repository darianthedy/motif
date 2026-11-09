import XCTest
import SwiftUI
@testable import Motif

/// The Duo plan's D02 navigation model: one sidebar selection, detail path and
/// column visibility per tab, all in `AppState` so a fold never loses them.
@MainActor final class NavigationModelTests: XCTestCase {
    private func makeApp() -> AppState {
        let storage = testStorage()
        let store = LibraryStore(account: TestAccount(nil, MemoryBackend()), cache: Cache(storage: storage), outbox: Outbox(storage: storage),
                                 defaults: UserDefaults(suiteName: "nav-" + newID())!)
        return AppState(store: store)
    }
    func testAFullRouteSplitsIntoSelectionAndPath() {
        let app = makeApp()
        app.openPuzzles([.collection("c1"), .puzzles("c1"), .puzzle("c1", "p1")])
        XCTAssertEqual(app.puzzlesCollection, "c1"); XCTAssertEqual(app.puzzlesPath, [.puzzles("c1"), .puzzle("c1", "p1")])
        // A route without a collection pushes on the current selection.
        app.openPuzzles([.puzzles("c1")])
        XCTAssertEqual(app.puzzlesCollection, "c1"); XCTAssertEqual(app.puzzlesPath, [.puzzles("c1")])
        app.openPuzzles([]); XCTAssertNil(app.puzzlesCollection); XCTAssertEqual(app.puzzlesPath, [])

        app.openGames([.collection("g1"), .game("g1", "game")])
        XCTAssertEqual(app.gamesCollection, "g1"); XCTAssertEqual(app.gamesPath, [.game("g1", "game")])
        app.openGames([.collection("g2")]); XCTAssertEqual(app.gamesCollection, "g2"); XCTAssertEqual(app.gamesPath, [])
    }
    func testSelectingInTheSidebarClearsThePath() {
        let app = makeApp()
        app.openPuzzles([.collection("c1"), .puzzles("c1")])
        app.puzzlesSelection = "c1"; XCTAssertEqual(app.puzzlesPath, [.puzzles("c1")], "Reselecting the same collection keeps the path")
        app.puzzlesSelection = "c2"; XCTAssertEqual(app.puzzlesCollection, "c2"); XCTAssertEqual(app.puzzlesPath, [])
        app.openGames([.collection("g1"), .game("g1", "game")])
        app.gamesSelection = nil; XCTAssertNil(app.gamesCollection); XCTAssertEqual(app.gamesPath, [])
    }
    func testABoardHidesTheSidebarAndPoppingRestoresIt() {
        let app = makeApp()
        app.puzzlesColumns.visibility = .all
        app.openPuzzles([.collection("c1"), .puzzles("c1")]); XCTAssertEqual(app.puzzlesColumns.visibility, .all)
        app.puzzlesPath.append(.puzzle("c1", "p1")); XCTAssertEqual(app.puzzlesColumns.visibility, .detailOnly)
        app.puzzlesPath.removeLast(); XCTAssertEqual(app.puzzlesColumns.visibility, .all)

        app.openGames([.collection("g1"), .game("g1", "game")]); XCTAssertEqual(app.gamesColumns.visibility, .detailOnly)
        app.openGames([]); XCTAssertEqual(app.gamesColumns.visibility, .automatic)
    }
    func testCollapsingAndExpandingKeepsTheSelectionAndThePushedPuzzle() {
        let app = makeApp()
        app.openPuzzles([.collection("c1"), .puzzles("c1"), .puzzle("c1", "p1")])
        // Folding collapses the split view to one stack and unfolding expands it again; the system
        // may rewrite the column visibility meanwhile, but owns neither the selection nor the path.
        app.puzzlesColumns.visibility = .automatic
        app.puzzlesColumns.visibility = .detailOnly
        XCTAssertEqual(app.puzzlesCollection, "c1")
        XCTAssertEqual(app.puzzlesPath, [.puzzles("c1"), .puzzle("c1", "p1")])
        app.puzzlesPath.removeLast(); XCTAssertEqual(app.puzzlesColumns.visibility, .automatic)
    }
    func testSignOutClearsBothTabs() async throws {
        let app = makeApp()
        await app.store.open(); try await app.store.signIn("u", "p")
        app.openPuzzles([.collection("c1"), .puzzles("c1")]); app.openGames([.collection("g1")])
        await app.signOut()
        XCTAssertNil(app.puzzlesCollection); XCTAssertEqual(app.puzzlesPath, [])
        XCTAssertNil(app.gamesCollection); XCTAssertEqual(app.gamesPath, [])
    }
}
