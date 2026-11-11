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
        app.openGames([]); XCTAssertEqual(app.gamesColumns.visibility, .all)
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
        app.puzzlesPath.removeLast(); XCTAssertEqual(app.puzzlesColumns.visibility, .all)
    }
    /// Decision 16: with nothing selected the sidebar shows. `.automatic` left it hidden on IL and
    /// the iPad, at launch and after a sheet or an alert.
    /// Decision 16, open tall (IP, FT, iPad portrait): a selected collection rests detail only,
    /// nothing selected shows the sidebar, a board still hides it, and going wide shows it again.
    func testOpenTallShowsTheDetailAloneOnceACollectionIsSelected() {
        let app = makeApp()
        app.setOpenTall(true)
        XCTAssertEqual(app.puzzlesColumns.visibility, .all, "Nothing selected: the sidebar shows")
        app.openPuzzles([.collection("c1")]); XCTAssertEqual(app.puzzlesColumns.visibility, .detailOnly)
        app.puzzlesColumns.visibility = .all   // the sidebar button slides it over the detail
        app.puzzlesSelection = "c2"; XCTAssertEqual(app.puzzlesColumns.visibility, .detailOnly, "Picking a collection closes the overlay")
        app.puzzlesPath = [.puzzles("c2"), .puzzle("c2", "p1")]; XCTAssertEqual(app.puzzlesColumns.visibility, .detailOnly)
        app.setOpenTall(false); app.puzzlesPath = []
        XCTAssertEqual(app.puzzlesColumns.visibility, .all, "Wide again: two columns once the board is popped")
        app.openGames([.collection("g1")]); XCTAssertEqual(app.gamesColumns.visibility, .all)
        app.setOpenTall(true); XCTAssertEqual(app.gamesColumns.visibility, .detailOnly)
        app.openGames([]); XCTAssertEqual(app.gamesColumns.visibility, .all)
    }
    func testTheSidebarShowsUntilABoardHidesIt() {
        let app = makeApp()
        XCTAssertEqual(app.puzzlesColumns.visibility, .all); XCTAssertEqual(app.gamesColumns.visibility, .all)
    }
    /// A launch route opens before the tabs exist, with its selection and its path in one go,
    /// and only once the library is in.
    func testALaunchRouteOpensItsSelectionAndPathOnceTheLibraryIsIn() async throws {
        let storage = testStorage()
        let store = LibraryStore(account: TestAccount(nil, MemoryBackend()), cache: Cache(storage: storage), outbox: Outbox(storage: storage),
                                 defaults: UserDefaults(suiteName: "nav-" + newID())!)
        let app = AppState(store: store, route: "game-eval")
        XCTAssertTrue(app.awaitingLaunchRoute)
        app.openLaunchRoute(); XCTAssertTrue(app.awaitingLaunchRoute, "Nothing to open before the library loads")
        await app.store.open(); try await app.store.signIn("u", "p")
        let collection = GameCollection(id: "g1", name: "Games", createdAt: 1)
        _ = await app.edit { try await $0.createGameCollections([collection]) }
        _ = await app.edit { try await $0.addGames([NewGame(id: "game", collectionId: "g1", position: 0, pgn: "1. e4 e5 *", orientation: .white)]) }
        XCTAssertEqual(app.store.library?.games.map(\.id), ["game"])
        app.openLaunchRoute()
        XCTAssertFalse(app.awaitingLaunchRoute)
        XCTAssertEqual(app.gamesCollection, "g1"); XCTAssertEqual(app.gamesPath, [.game("g1", "game")])
        XCTAssertEqual(app.gamesColumns.visibility, .detailOnly)
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
