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
    func testSearchAndSelectAll() {
        let model = GameCollectionModel(), alpha = Game(id: "a", collectionId: "c", position: 0, pgn: "[White \"Alpha\"]\n1. e4 *", orientation: .white, addedAt: 0)
        let beta = Game(id: "b", collectionId: "c", position: 1, pgn: "[White \"Beta\"]\n1. d4 *", orientation: .white, addedAt: 0)
        model.query = "alpha"; XCTAssertEqual(model.shown([alpha, beta]), [alpha])
        model.query = "missing"; XCTAssertEqual(model.shown([alpha, beta]), [])
        model.query = ""; model.toggleAll([alpha, beta]); XCTAssertEqual(model.selected, ["a", "b"]); XCTAssertTrue(model.allSelected([alpha, beta]))
        model.toggleAll([alpha]); XCTAssertEqual(model.selected, ["b"]); XCTAssertFalse(model.allSelected([alpha, beta]))
    }
    func testDragReorderRenumbersOnlyMovedGames() {
        let model = GameCollectionModel()
        let games = ["a", "b", "c"].enumerated().map { Game(id: $1, collectionId: "c", position: $0, pgn: "1. e4 *", orientation: .white, addedAt: 0) }
        XCTAssertEqual(model.placements(games, from: [2], to: 0), [GamePlacement(id: "c", collectionId: "c", position: 0),
                                                                  GamePlacement(id: "a", collectionId: "c", position: 1),
                                                                  GamePlacement(id: "b", collectionId: "c", position: 2)])
        XCTAssertEqual(model.placements(games, from: [0], to: 2), [GamePlacement(id: "b", collectionId: "c", position: 0),
                                                                  GamePlacement(id: "a", collectionId: "c", position: 1)])
        XCTAssertEqual(model.placements(games, from: [1], to: 1), [])
    }
    func testDragReorderPersistsViaPlaceGames() async throws {
        let paths = testStorage(), backend = MemoryBackend()
        try await backend.createGameCollections([GameCollection(id: "c", name: "C", createdAt: 0)])
        try await backend.addGames(["a", "b", "c"].enumerated().map { NewGame(id: $1, collectionId: "c", position: $0, pgn: "1. e4 *", orientation: .white) })
        let store = LibraryStore(account: TestAccount(User(id: "u", email: "e"), backend), cache: Cache(storage: paths), outbox: Outbox(storage: paths), defaults: UserDefaults(suiteName: newID())!)
        await store.open(); let app = AppState(store: store), model = GameCollectionModel()
        let games = gamesIn(try XCTUnwrap(store.library), "c")
        let saved = await model.reorder(app, games: games, from: [2], to: 0); XCTAssertTrue(saved)
        XCTAssertEqual(gamesIn(try XCTUnwrap(store.library), "c").map(\.id), ["c", "a", "b"]); XCTAssertNil(model.pendingOrder)
        model.query = "anything"; let filtered = await model.reorder(app, games: games, from: [0], to: 3); XCTAssertFalse(filtered)
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
