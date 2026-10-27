import XCTest
@testable import Motif

@MainActor final class PuzzleManagementTests: XCTestCase {
    private let json = #"{"collection":"Book","puzzles":[{"fen":"6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1","solutions":[["a1a8"]],"comment":"new"}]}"#
    func testSingleGroupTargetsExistingCollectionAndRefreshesContentInPlace() {
        let model = ImportModel(); model.text = json; model.parse(); model.collectionId = "c1"
        let batch = model.plan(testDataLibrary(), now: 10)
        XCTAssertEqual(batch.collections, []); XCTAssertEqual(batch.added, 0)
        XCTAssertEqual(batch.puzzles.first?.position, 0); XCTAssertEqual(batch.puzzles.first?.comment, "new")
        XCTAssertEqual(batch.description, "No new puzzles — refreshed 1 you already had.")
    }
    func testMultipleGroupsKeepTheirNamesOrderAndDistinctCollections() {
        let model = ImportModel(); model.text = "[\(json),\(json.replacingOccurrences(of: "Book", with: "Chapter"))]"; model.parse()
        model.name = "Ignored"; model.collectionId = "c1"
        let batch = model.plan(testDataLibrary(), now: 10)
        XCTAssertTrue(model.multi); XCTAssertEqual(batch.collections.map(\.name), ["Book", "Chapter"])
        XCTAssertEqual(batch.collections.map(\.createdAt), [10, 11]); XCTAssertEqual(Set(batch.puzzles.map(\.collectionId)).count, 2)
        XCTAssertEqual(batch.added, 2)
    }
    func testInvalidRowsRemainVisibleAndEmptyPasteClearsPreview() {
        let model = ImportModel(); model.text = #"{"puzzles":[{"fen":"bad"}]}"#; model.parse()
        XCTAssertEqual(model.incoming, 0); XCTAssertEqual(model.result?.rejected.first?.reason, "Malformed FEN")
        model.text = " "; model.parse(); XCTAssertNil(model.result)
    }
    func testOfflineApplyMakesNoChangesAndOnlineApplyPersists() async throws {
        let paths = testStorage(), backend = MemoryBackend(testDataLibrary())
        let store = LibraryStore(account: TestAccount(User(id: "u", email: "e"), backend), cache: Cache(storage: paths), outbox: Outbox(storage: paths), defaults: UserDefaults(suiteName: newID())!)
        await store.open(); let app = AppState(store: store), model = ImportModel()
        model.text = json; model.parse(); model.collectionId = "c1"
        store.online = false; let offline = await model.apply(app); XCTAssertFalse(offline)
        XCTAssertNotEqual(store.library?.puzzles.first?.comment, "new")
        store.online = true; let saved = await model.apply(app); XCTAssertTrue(saved)
        XCTAssertEqual(store.library?.puzzles.first?.comment, "new")
    }
    func testDetailReplaysEveryLineAndSwitchingRewinds() {
        let puzzle = testPuzzle([["a1a8"], ["a1a2"]]), model = PuzzleDetailModel(puzzle)
        model.ply = 1; XCTAssertEqual(Board.pieceAt(model.fen, "a8")?.type, .rook)
        model.lineIndex = 1; XCTAssertEqual(model.ply, 0); XCTAssertEqual(model.fen, puzzle.fen)
        model.ply = 1; XCTAssertEqual(Board.pieceAt(model.fen, "a2")?.type, .rook)
    }
    func testPuzzleListSearchMatchesNumberAndMotifWithinTheScope() {
        func puzzle(_ id: String, source: String?, tags: [String], flagged: Bool = false) -> Puzzle {
            var puzzle = testPuzzle([["a1a8"]]); puzzle.id = id; puzzle.sourceId = source; puzzle.tags = tags; puzzle.flagged = flagged; return puzzle
        }
        let puzzles = [puzzle("a", source: "00412", tags: ["mateIn2", "backRank"]), puzzle("b", source: nil, tags: ["fork"], flagged: true),
                       puzzle("c", source: "00977", tags: ["backRank"])]
        let records = puzzleRecords([testDataAttempt("x", puzzleId: "a"),
                                     Attempt(id: "y", puzzleId: "c", runId: nil, result: .failed, mistakes: 1, hinted: false, playedAt: 2)])
        let model = PuzzleListModel()
        XCTAssertEqual(model.items(puzzles, records).map(\.number), ["00412", "2", "00977"])
        model.query = "#412"; XCTAssertEqual(model.items(puzzles, records).map(\.id), ["a"])
        model.query = "back rank"; XCTAssertEqual(model.items(puzzles, records).map(\.id), ["a", "c"])
        model.query = "2"; XCTAssertEqual(model.items(puzzles, records).map(\.id), ["a", "b"])
        model.scope = .review; model.query = "BackRank"; XCTAssertEqual(model.items(puzzles, records).map(\.id), ["c"])
        model.scope = .solved; XCTAssertEqual(model.items(puzzles, records).map(\.id), ["a"])
        model.scope = .new; XCTAssertEqual(model.items(puzzles, records).map(\.id), [])
        model.query = ""; XCTAssertEqual(model.items(puzzles, records).map(\.id), ["b"])
        model.scope = .flagged; XCTAssertEqual(model.items(puzzles, records).map(\.id), ["b"])
        model.query = "mate"; XCTAssertTrue(model.items(puzzles, records).isEmpty)
        XCTAssertEqual(motifLabel("mateIn2"), "Mate in 2"); XCTAssertEqual(motifLabel("backRank"), "back rank")
    }
}
