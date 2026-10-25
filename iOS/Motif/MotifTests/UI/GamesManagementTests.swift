import XCTest
@testable import Motif

@MainActor final class GamesManagementTests: XCTestCase {
    func testAddKeepsValidGamesAndReportsBrokenGames() {
        let model = AddGamesModel()
        model.text = "[White \"A\"]\n1. e4 *\n\n[White \"Broken\"]\n1. e9 *\n\n[White \"B\"]\n1. d4 *"
        XCTAssertEqual(model.read?.games.count, 2); XCTAssertEqual(model.read?.errors.count, 1)
        XCTAssertTrue(model.read?.errors.first?.message.contains("e9") == true)
        model.fen = "bad"; XCTAssertFalse(model.fenCheck.ok)
    }
    func testExportAndSafeNamesPreservePgnBytes() {
        let game = Game(id: "a", collectionId: "c", position: 0, pgn: "1. e4 *\n ", orientation: .white, addedAt: 0)
        XCTAssertEqual(gamesAsFile([game, game]), "1. e4 *\n\n1. e4 *\n")
        XCTAssertEqual(pgnFileName(" A/B:*?  C "), "AB C.pgn"); XCTAssertEqual(pgnFileName("/"), "games.pgn")
    }
    func testSearchSelectionAndModeChanges() {
        let model = GameCollectionModel(), game = Game(id: "a", collectionId: "c", position: 0, pgn: "[White \"Alpha\"]\n1. e4 *", orientation: .white, addedAt: 0)
        model.query = "alpha"; XCTAssertEqual(model.shown([game]), [game])
        model.query = "missing"; XCTAssertEqual(model.shown([game]), [])
        model.toggle("a"); XCTAssertEqual(model.selected, ["a"])
        model.mode = .reorder; XCTAssertTrue(model.selected.isEmpty); XCTAssertEqual(model.shown([game]), [game])
    }
    func testOfflineAddIsDisabledAndNewFenGameKeepsBlackOrientation() async throws {
        let paths = testStorage(), backend = MemoryBackend()
        try await backend.createGameCollections([GameCollection(id: "c", name: "C", createdAt: 0)])
        let store = LibraryStore(account: TestAccount(User(id: "u", email: "e"), backend), cache: Cache(storage: paths), outbox: Outbox(storage: paths), defaults: UserDefaults(suiteName: newID())!)
        await store.open(); let app = AppState(store: store), model = AddGamesModel()
        model.fen = "6k1/5ppp/8/8/8/8/8/R5K1 b - - 0 1"
        store.online = false; let offline = await model.add(app, collectionId: "c", newBoard: true); XCTAssertNil(offline)
        store.online = true; let id = await model.add(app, collectionId: "c", newBoard: true); XCTAssertNotNil(id)
        let game = try XCTUnwrap(store.library?.games.first)
        XCTAssertEqual(game.orientation, .black); XCTAssertEqual(try parsePgn(game.pgn).startFen, model.start)
    }
    func testBulkCopyUsesNewIdsAndMoveRetainsIdentity() async throws {
        let paths = testStorage(), backend = MemoryBackend()
        try await backend.createGameCollections([GameCollection(id: "c", name: "C", createdAt: 0), GameCollection(id: "d", name: "D", createdAt: 1)])
        try await backend.addGames([NewGame(id: "g", collectionId: "c", position: 0, pgn: "1. e4 *", orientation: .white)])
        let store = LibraryStore(account: TestAccount(User(id: "u", email: "e"), backend), cache: Cache(storage: paths), outbox: Outbox(storage: paths), defaults: UserDefaults(suiteName: newID())!)
        await store.open(); let app = AppState(store: store), model = GameCollectionModel(), games = gamesIn(try XCTUnwrap(store.library), "c")
        model.selected = ["g"]; let copied = await model.bulk(app, games: games, target: "d", copy: true); XCTAssertTrue(copied)
        let copy = try XCTUnwrap(store.library?.games.first { $0.collectionId == "d" }); XCTAssertNotEqual(copy.id, "g")
        model.selected = ["g"]; let moved = await model.bulk(app, games: games, target: "d", copy: false); XCTAssertTrue(moved)
        XCTAssertEqual(store.library?.games.first { $0.id == "g" }?.collectionId, "d")
    }
}
