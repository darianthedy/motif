import XCTest
@testable import Motif

/// One case for every games/library.test.ts case.
final class GameLibraryTests: XCTestCase {
    private var library: Library {
        testGameLibrary([testStoredGame("x", "a", 0), testStoredGame("y", "a", 3), testStoredGame("z", "b", 0)])
    }
    func testListsACollectionInItsOrder() {
        XCTAssertEqual(gamesIn(library, "a").map(\.id), ["x", "y"])
    }
    func testAppendsNewGamesAfterTheLastWithNewIds() {
        let added = appendGames(library, "a", [GameContent(pgn: "1. e4 *", orientation: .white),
                                              GameContent(pgn: "1. d4 *", orientation: .black)])
        XCTAssertEqual(added.map(\.collectionId), ["a", "a"])
        XCTAssertEqual(added.map(\.position), [4, 5])
        XCTAssertEqual(added.map(\.orientation), [.white, .black])
        XCTAssertEqual(Set(added.map(\.id)).count, 2)
    }
    func testCopiesGamesLeavingTheOriginalsWhereTheyAre() {
        let copies = copyGames(library, gamesIn(library, "a"), "b")
        XCTAssertEqual(copies.map(\.collectionId), ["b", "b"])
        XCTAssertEqual(copies.map(\.position), [1, 2])
        XCTAssertFalse(copies.contains { $0.id == "x" || $0.id == "y" })
    }
    func testMovesGamesToAnotherCollectionSkippingThoseAlreadyThere() {
        XCTAssertEqual(moveGames(library, [library.games[0], library.games[2]], "b"),
                       [GamePlacement(id: "x", collectionId: "b", position: 1)])
    }
    func testSwapsWithANeighbourAndDoesNothingAtEitherEnd() {
        let expected = [GamePlacement(id: "y", collectionId: "a", position: 0),
                        GamePlacement(id: "x", collectionId: "a", position: 1)]
        XCTAssertEqual(shiftGame(library, library.games[1], .up), expected)
        XCTAssertEqual(shiftGame(library, library.games[0], .down), expected)
        XCTAssertEqual(shiftGame(library, library.games[0], .up), [])
        XCTAssertEqual(shiftGame(library, library.games[1], .down), [])
    }
}
