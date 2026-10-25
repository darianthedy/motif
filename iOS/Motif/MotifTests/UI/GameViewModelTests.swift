import XCTest
@testable import Motif

@MainActor final class GameViewModelTests: XCTestCase {
    private func game(_ pgn: String = "1. e4 e5 2. Nf3 *") -> Game { Game(id: "g", collectionId: "c", position: 0, pgn: pgn, orientation: .white, addedAt: 0) }
    func testPlayExtendsAtEndBranchesAtEarlierPositionAndVisitsExistingMovesWithoutSaving() async throws {
        var writes: [String] = []
        let model = GameViewModel(game()) { changes in if let pgn = changes.pgn { writes.append(pgn) }; return true }
        model.next(); XCTAssertEqual(model.path, [0])
        model.play(try uci("e7e5")); XCTAssertEqual(model.path, [0, 0]); XCTAssertEqual(model.pending, 0)
        model.end(); model.play(try uci("b8c6")); await model.waitForSaves()
        XCTAssertEqual(model.node?.san, "Nc6"); XCTAssertEqual(writes.count, 1)
        model.go([]); model.play(try uci("c2c4")); await model.waitForSaves()
        XCTAssertEqual(model.path, [1]); XCTAssertEqual(model.tree?.moves.map(\.san), ["e4", "c4"])
    }
    func testDeleteRemovesSubtreeAndSelectsParent() async throws {
        let model = GameViewModel(game()) { _ in true }
        model.go([0, 0]); model.deleteHere(); await model.waitForSaves()
        XCTAssertEqual(model.path, [0]); XCTAssertTrue(model.node?.children.isEmpty == true)
        XCTAssertFalse(writePgn(try XCTUnwrap(model.tree)).contains("Nf3"))
    }
    func testPromoteRetainsCursorAndBothLines() async throws {
        let model = GameViewModel(game("1. e4 (1. c4 e5) e5 *")) { _ in true }
        model.go([1, 0]); model.promote(); await model.waitForSaves()
        XCTAssertEqual(model.path, [0, 0]); XCTAssertEqual(model.tree?.moves.map(\.san), ["c4", "e4"])
        XCTAssertEqual(model.node?.san, "e5")
    }
    func testRapidEditsUploadInOrderAndLastSnapshotContainsBothChanges() async throws {
        var writes: [String] = [], first = true
        let model = GameViewModel(game()) { changes in
            if first { first = false; try? await Task.sleep(for: .milliseconds(30)) }
            if let pgn = changes.pgn { writes.append(pgn) }; return true
        }
        model.play(try uci("c2c4")); model.play(try uci("e7e5"))
        XCTAssertEqual(model.pending, 2); await model.waitForSaves()
        XCTAssertEqual(writes.count, 2); XCTAssertEqual(model.pending, 0)
        let a = try parsePgn(writes[0]), b = try parsePgn(writes[1])
        XCTAssertTrue(a.moves[1].children.isEmpty); XCTAssertEqual(b.moves[1].children.first?.san, "e5")
    }
    func testOfflineReadOnlyAndFailedSaveReturnsToStoredCopy() async throws {
        let original = game(), model = GameViewModel(game(), online: false) { _ in false }
        model.play(try uci("c2c4")); model.flip(); model.comment("blocked")
        XCTAssertEqual(model.pending, 0); XCTAssertEqual(model.orientation, .white); XCTAssertEqual(model.tree, try parsePgn(original.pgn))
        model.online = true; model.play(try uci("c2c4")); await model.waitForSaves()
        XCTAssertEqual(model.tree, try parsePgn(original.pgn)); XCTAssertEqual(model.path, [])
    }
    func testCommentsAndHeadersPersistPgnCommandsWhileDisplayHidesThem() async throws {
        var saved: String?
        let model = GameViewModel(game()) { changes in saved = changes.pgn; return true }
        model.next(); model.comment("Idea [%clk 0:05] [%eval 0.4]")
        model.details(PgnHeaders([("White", "Player"), ("Result", "1-0")]))
        await model.waitForSaves()
        XCTAssertEqual(model.comment, "Idea"); XCTAssertTrue(saved?.contains("[%clk 0:05]") == true)
        XCTAssertEqual(model.tree?.headers["White"], "Player"); XCTAssertEqual(model.tree?.headers["Result"], "1-0")
    }
}
