import XCTest
@testable import Motif

/// Scan plan S04: the import sheet's model, the shown answer, starting runs and the launch routes.
@MainActor final class ScanTabTests: XCTestCase {
    private func file(_ contents: [ScanPuzzleContent], extra: String = "") throws -> String {
        let data = try JSONEncoder().encode(contents.map(FileEntry.init))
        let entries = String(decoding: data, as: UTF8.self).dropFirst().dropLast()
        return #"{"version":1,"scan":["# + entries + extra + "]}"
    }
    /// The file format's field names (not the stored `answer` nesting).
    private struct FileEntry: Encodable {
        let fenBefore: String, lastMove: String, flagged: Bool, quickScan: [ScanSquare], moves: [String: Int]
        init(_ content: ScanPuzzleContent) {
            fenBefore = content.fenBefore; lastMove = content.lastMove.text; flagged = content.answer.flagged
            quickScan = content.answer.quickScan; moves = content.answer.moves
        }
    }
    private func store(_ library: Library) async -> LibraryStore {
        let paths = testStorage()
        let store = LibraryStore(account: TestAccount(User(id: "u", email: "e"), MemoryBackend(library)), cache: Cache(storage: paths),
                                 outbox: Outbox(storage: paths), defaults: UserDefaults(suiteName: newID())!)
        await store.open(); return store
    }

    func testImportCountsNewUpdatedAndRejected() throws {
        var library = Library(); library.scanPuzzles = [testScanPuzzle("held", "e1d1")]
        let model = ScanImportModel()
        model.text = try file([testScanContent("e1d1"), testScanContent("e1f1")], extra: #",{"fenBefore":"bad"}"#); model.parse()
        XCTAssertEqual(model.incoming, 2)
        let batch = model.plan(library)
        XCTAssertEqual(batch.added, 1); XCTAssertEqual(batch.updated, 1); XCTAssertEqual(batch.rejected, 1)
        XCTAssertEqual(batch.description, "1 added, 1 updated, 1 rejected.")
        model.text = "  "; model.parse(); XCTAssertNil(model.result)
    }
    func testBatchDescriptionLeavesOutZerosAndSaysWhenNothingIsAdded() {
        XCTAssertEqual(ScanImportBatch(puzzles: [testScanContent()], added: 1).description, "1 added.")
        XCTAssertEqual(ScanImportBatch(puzzles: [], added: 0, rejected: 2).description, "Nothing to add.")
    }
    func testImportNeedsAConnectionAndUpsertsIntoThePool() async throws {
        let store = await store(Library()), app = AppState(store: store), model = ScanImportModel()
        model.text = try file([testScanContent("e1d1"), testScanContent("e1f1")]); model.parse()
        store.online = false; let offline = await model.apply(app); XCTAssertFalse(offline)
        XCTAssertEqual(store.library?.scanPuzzles.count, 0)
        store.online = true; let saved = await model.apply(app); XCTAssertTrue(saved)
        XCTAssertEqual(store.library?.scanPuzzles.count, 2)
        // Sent again: updated, not duplicated.
        let again = await model.apply(app); XCTAssertTrue(again); XCTAssertEqual(store.library?.scanPuzzles.count, 2)
    }
    func testSummaryReadsTheSamplePuzzle() throws {
        let text = try String(contentsOf: try XCTUnwrap(Bundle.main.url(forResource: "sample-scan", withExtension: "json")), encoding: .utf8)
        let puzzles = ScanImport.read(text).puzzles; XCTAssertEqual(puzzles.count, 2)
        let summary = ScanPuzzleSummary(ScanPuzzle(id: "s", content: puzzles[0], addedAt: 0), index: 0)
        XCTAssertEqual(summary.number, "two-knights"); XCTAssertEqual(summary.solver, .white)
        XCTAssertEqual(summary.lastMove, "3... Nf6"); XCTAssertEqual(summary.call, "Flag")
        XCTAssertEqual(summary.quickScan, "e4 attacked"); XCTAssertEqual(summary.bestMoves, ["d3"])
        XCTAssertEqual(summary.bestLine, "4. d3")
        let quiet = ScanPuzzleSummary(ScanPuzzle(id: "q", content: puzzles[1], addedAt: 0), index: 1)
        XCTAssertEqual(quiet.call, "No Flag"); XCTAssertEqual(quiet.quickScan, "Nothing")
    }
    func testDetailMarksTheMakersAnswer() {
        let answer = ScanAnswer(flagged: true, quickScan: [ScanSquare(square: "e4", kind: .attacked)],
                                targets: ScanTargets(red: ["f7"], orange: ["e5"], kingZone: ["g7"], fork: ["d5"]),
                                arrows: [ScanArrow(from: "f3", to: "g5", side: .own, kind: .threat)], moves: [:])
        let marks = ScanPuzzleDetailView.annotations(answer)
        XCTAssertEqual(marks.tints, ["e4": .quickScan, "f7": .red, "e5": .orange])
        // No king-zone dots (v4): g7 isn't drawn.
        XCTAssertEqual(marks.dots, ["d5"]); XCTAssertEqual(marks.arrows, [BoardArrow(from: "f3", to: "g5", side: .own)])
    }
    func testStartAndReviewOpenRunsThroughTheOutbox() async {
        var library = Library()
        library.scanPuzzles = [testScanPuzzle("s1", "e1d1"), testScanPuzzle("s2", "e1f1", addedAt: 1)]
        library.scanAttempts = [testScanAttempt("a", "s2", .failed)]
        let store = await store(library), app = AppState(store: store)
        store.online = false
        await app.beginScan(SCOPE_ALL, .randomGlobal)
        XCTAssertEqual(app.scanSession?.scope, SCOPE_ALL)
        XCTAssertEqual(Set(scanRunIn(store.library!, SCOPE_ALL)?.queue ?? []), ["s1", "s2"])
        XCTAssertTrue(scanResumable(store.library!, SCOPE_ALL))
        await app.beginScan(SCOPE_REVIEW, .reviewMistakes)
        XCTAssertEqual(scanRunIn(store.library!, SCOPE_REVIEW)?.queue, ["s2"])
        // Puzzle runs are untouched.
        XCTAssertTrue(store.library!.runs.isEmpty)
    }
    func testNothingToReviewStartsNothing() async {
        var library = Library(); library.scanPuzzles = [testScanPuzzle("s1")]
        let store = await store(library), app = AppState(store: store)
        await app.beginScan(SCOPE_REVIEW, .reviewMistakes)
        XCTAssertNil(app.scanSession); XCTAssertTrue(store.library!.scanRuns.isEmpty)
    }
    func testScanLaunchRoutesOpenTheScanTab() async {
        var library = Library(); library.scanPuzzles = [testScanPuzzle("s1")]
        let store = await store(library)
        XCTAssertEqual(AppState(store: store, route: "scan").tab, .scan)
        XCTAssertEqual(AppState(store: store, route: "scan-board").tab, .puzzles)
        let list = AppState(store: store, route: "scan-list"); list.openLaunchRoute(); XCTAssertEqual(list.scanPath, [.puzzles])
        let detail = AppState(store: store, route: "scan-detail:s1"); detail.openLaunchRoute()
        XCTAssertEqual(detail.scanPath, [.puzzles, .puzzle("s1")])
        let importing = AppState(store: store, route: "scan-import"); importing.openLaunchRoute(); XCTAssertTrue(importing.importingScan)
    }
}
