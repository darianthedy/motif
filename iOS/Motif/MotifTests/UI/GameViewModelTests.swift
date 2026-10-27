import XCTest
@testable import Motif

@MainActor final class GameViewModelTests: XCTestCase {
    private func game(_ pgn: String = "1. e4 e5 2. Nf3 *") -> Game { Game(id: "g", collectionId: "c", position: 0, pgn: pgn, orientation: .white, addedAt: 0) }
    func testPlayExtendsAtEndBranchesAtEarlierPositionAndVisitsExistingMovesWithoutChanging() async throws {
        let model = GameViewModel(game()) { _ in true }
        model.next(); XCTAssertEqual(model.path, [0])
        model.play(try uci("e7e5")); XCTAssertEqual(model.path, [0, 0]); XCTAssertFalse(model.unsaved)
        model.end(); model.play(try uci("b8c6"))
        XCTAssertEqual(model.node?.san, "Nc6"); XCTAssertTrue(model.unsaved)
        model.go([]); model.play(try uci("c2c4"))
        XCTAssertEqual(model.path, [1]); XCTAssertEqual(model.tree?.moves.map(\.san), ["e4", "c4"])
    }
    func testDeleteRemovesSubtreeAndSelectsParent() async throws {
        let model = GameViewModel(game()) { _ in true }
        model.go([0, 0]); model.deleteHere()
        XCTAssertEqual(model.path, [0]); XCTAssertTrue(model.node?.children.isEmpty == true)
        XCTAssertFalse(writePgn(try XCTUnwrap(model.tree)).contains("Nf3"))
    }
    func testPromoteRetainsCursorAndBothLines() async throws {
        let model = GameViewModel(game("1. e4 (1. c4 e5) e5 *")) { _ in true }
        model.go([1, 0]); model.promote()
        XCTAssertEqual(model.path, [0, 0]); XCTAssertEqual(model.tree?.moves.map(\.san), ["c4", "e4"])
        XCTAssertEqual(model.node?.san, "e5")
    }
    func testEditsWaitForSaveWhichSendsOneSnapshotOfEverything() async throws {
        var writes: [GameChanges] = []
        let model = GameViewModel(game()) { changes in writes.append(changes); return true }
        XCTAssertFalse(model.canSave)
        model.play(try uci("c2c4")); model.play(try uci("e7e5")); model.flip()
        XCTAssertTrue(writes.isEmpty); XCTAssertTrue(model.canSave)
        let saved = await model.save()
        XCTAssertTrue(saved); XCTAssertFalse(model.unsaved); XCTAssertEqual(writes.count, 1)
        let tree = try parsePgn(try XCTUnwrap(writes[0].pgn))
        XCTAssertEqual(tree.moves[1].children.first?.san, "e5"); XCTAssertEqual(writes[0].orientation, .black)
        model.flip(); _ = await model.save()
        XCTAssertNil(writes[1].pgn); XCTAssertEqual(writes[1].orientation, .white)
    }
    func testEditDuringUploadStaysUnsaved() async throws {
        let model = GameViewModel(game()) { _ in try? await Task.sleep(for: .milliseconds(30)); return true }
        model.play(try uci("c2c4"))
        let upload = Task { await model.save() }
        await Task.yield(); XCTAssertTrue(model.saving); XCTAssertFalse(model.canSave)
        model.go([1]); model.play(try uci("e7e5"))
        _ = await upload.value
        XCTAssertTrue(model.unsaved); XCTAssertEqual(model.node?.san, "e5")
    }
    func testDiscardReturnsToStoredCopyAndReceiveKeepsADraft() async throws {
        let original = game(), model = GameViewModel(game()) { _ in true }
        model.play(try uci("c2c4")); model.flip()
        var newer = original; newer.pgn = "1. d4 *"
        model.receive(newer); XCTAssertEqual(model.tree?.moves.map(\.san), ["e4", "c4"])
        model.discard()
        XCTAssertFalse(model.unsaved); XCTAssertEqual(model.orientation, .white); XCTAssertEqual(model.tree, try parsePgn("1. d4 *"))
        newer.pgn = original.pgn; model.receive(newer); XCTAssertEqual(model.tree, try parsePgn(original.pgn))
    }
    func testOfflineEditsStayInTheDraftAndFailedSaveKeepsIt() async throws {
        var writes = 0
        let model = GameViewModel(game(), online: false) { _ in writes += 1; return false }
        model.play(try uci("c2c4")); model.flip(); model.comment("offline")
        XCTAssertTrue(model.unsaved); XCTAssertFalse(model.canSave); XCTAssertEqual(model.orientation, .black)
        let offline = await model.save(); XCTAssertFalse(offline); XCTAssertEqual(writes, 0)
        model.online = true
        let failed = await model.save()
        XCTAssertFalse(failed); XCTAssertEqual(writes, 1); XCTAssertTrue(model.unsaved); XCTAssertEqual(model.tree?.moves.map(\.san), ["e4", "c4"])
    }
    func testCommentsAndHeadersPersistPgnCommandsWhileDisplayHidesThem() async throws {
        var saved: String?
        let model = GameViewModel(game()) { changes in saved = changes.pgn; return true }
        model.next(); model.comment("Idea [%clk 0:05] [%eval 0.4]")
        model.details(PgnHeaders([("White", "Player"), ("Result", "1-0")]))
        await model.save()
        XCTAssertEqual(model.comment, "Idea"); XCTAssertTrue(saved?.contains("[%clk 0:05]") == true)
        XCTAssertEqual(model.tree?.headers["White"], "Player"); XCTAssertEqual(model.tree?.headers["Result"], "1-0")
    }
}
