import XCTest
@testable import Motif

/// The 20 shared backend cases, each run against memory and RestBackend.
/// The four access-rules cases stay in Postgres/web because they test RLS.
final class BackendSuiteTests: XCTestCase {
    private func each(_ run: (any Backend) async throws -> Void) async throws {
        let backends: [any Backend] = [MemoryBackend(), RestBackend(rest: MemoryRest(), userId: "test")]
        for backend in backends { try await run(backend) }
    }
    private func collection(_ name: String = "Back rank") -> Collection { Collection(id: newID(), name: name, createdAt: 1234) }
    private func puzzle(_ id: String, _ n: Int, comment: String? = nil) -> NewPuzzle {
        NewPuzzle(testContent([[n == 0 ? "a1a8" : "a1a7"]], comment: comment), collectionId: id, position: n)
    }
    private func seeded(_ b: any Backend, _ n: Int = 2) async throws -> (Collection, [Puzzle]) {
        let c = collection()
        try await b.createCollections([c])
        return (c, try await b.importPuzzles((0..<n).map { puzzle(c.id, $0) }))
    }
    private func run(_ scope: String, _ queue: [String], _ time: Int64 = 2000) -> Run {
        Run(id: newID(), scope: scope, mode: .ordered, queue: queue, startedAt: time)
    }
    private func attempt(_ id: String, runId: String? = nil) -> Attempt {
        Attempt(id: newID(), puzzleId: id, runId: runId, result: .solved, mistakes: 0, hinted: false, playedAt: 3000)
    }
    private func seededGames(_ b: any Backend, _ count: Int = 2) async throws -> (GameCollection, [NewGame]) {
        let c = GameCollection(id: newID(), name: "Openings", createdAt: 1234)
        try await b.createGameCollections([c])
        let games = (0..<count).map { NewGame(id: newID(), collectionId: c.id, position: $0, pgn: "1. e4 e5 (1... c5) *\n", orientation: .white) }
        try await b.addGames(games)
        return (c, games)
    }
    func testStoresAndLoadsEveryKindOfRow() async throws {
        try await each { b in
            let c = self.collection("Mates"); try await b.createCollections([c])
            var p = self.puzzle(c.id, 0, comment: "No luft"); p.tags = ["mate"]; p.rating = 900; p.sourceId = "187"
            let first = try await b.importPuzzles([p])[0]
            let missing = NewPuzzle(testContent([], addPiece: missingKnight), collectionId: c.id, position: 1)
            let second = try await b.importPuzzles([missing])[0]
            let r = self.run(c.id, [first.id, second.id]); try await b.saveRun(r)
            var a = self.attempt(first.id, runId: r.id); a.result = .failed; a.mistakes = 2; a.hinted = true
            try await b.recordAttempts([a])
            let lib = try await b.load()
            XCTAssertEqual(lib.collections, [c]); XCTAssertEqual(lib.puzzles.count, 2)
            XCTAssertEqual(lib.puzzles.first?.content, first.content)
            XCTAssertEqual(lib.puzzles.last?.addPiece, missingKnight)
            XCTAssertEqual(lib.runs, [r]); XCTAssertEqual(lib.attempts, [a])
        }
    }
    func testRenamesACollectionAndLetsTwoShareAName() async throws {
        try await each { b in
            let a = self.collection("Same"), c = self.collection("Same"); try await b.createCollections([a, c])
            try await b.renameCollection(a.id, "Other")
            let lib = try await b.load(); XCTAssertEqual(lib.collections.map(\.name).sorted(), ["Other", "Same"])
        }
    }
    func testUpdatesAReimportedPuzzleInTheSameCollection() async throws {
        try await each { b in
            let (c, puzzles) = try await self.seeded(b, 1)
            try await b.setComment(puzzles[0].id, "mine")
            var incoming = self.puzzle(c.id, 0, comment: "from file"); incoming.tags = ["new"]; incoming.rating = 1500; incoming.sourceId = "9"
            let again = try await b.importPuzzles([incoming])[0]
            XCTAssertEqual(again.id, puzzles[0].id); XCTAssertEqual(again.addedAt, puzzles[0].addedAt)
            XCTAssertEqual(again.tags, ["new"]); XCTAssertEqual(again.comment, "from file")
            XCTAssertEqual(again.rating, 1500); XCTAssertEqual(again.sourceId, "9")
            let lib = try await b.load(); XCTAssertEqual(lib.puzzles.count, 1)
        }
    }
    func testKeepsOnePuzzleListedTwiceInAnImport() async throws {
        try await each { b in
            let c = self.collection(); try await b.createCollections([c])
            let stored = try await b.importPuzzles([self.puzzle(c.id, 0, comment: "first"), self.puzzle(c.id, 0, comment: "second")])
            XCTAssertEqual(stored.count, 1)
            let lib = try await b.load(); XCTAssertEqual(lib.puzzles.map(\.comment), ["second"])
        }
    }
    func testImportsTheSamePuzzleIntoTwoCollectionsAsTwoPuzzles() async throws {
        try await each { b in
            let a = self.collection("A"), c = self.collection("B"); try await b.createCollections([a, c])
            let first = try await b.importPuzzles([self.puzzle(a.id, 0)])[0], second = try await b.importPuzzles([self.puzzle(c.id, 0)])[0]
            XCTAssertNotEqual(first.id, second.id); let lib = try await b.load(); XCTAssertEqual(lib.puzzles.count, 2)
        }
    }
    func testSetsAndClearsAComment() async throws {
        try await each { b in
            let (_, p) = try await self.seeded(b, 1); try await b.setComment(p[0].id, "  a note ")
            var lib = try await b.load(); XCTAssertEqual(lib.puzzles[0].comment, "a note")
            try await b.setComment(p[0].id, "   "); lib = try await b.load(); XCTAssertNil(lib.puzzles[0].comment)
        }
    }
    func testFlagsUnflagsAndReimportKeepsTheFlag() async throws {
        try await each { b in
            let (c, p) = try await self.seeded(b, 1); XCTAssertNil(p[0].flagged)
            try await b.setFlagged(p[0].id, true); try await b.importPuzzles([self.puzzle(c.id, 0, comment: "again")])
            var lib = try await b.load(); XCTAssertEqual(lib.puzzles[0].flagged, true)
            try await b.setFlagged(p[0].id, false); lib = try await b.load(); XCTAssertNil(lib.puzzles[0].flagged)
        }
    }
    func testDeletesAPuzzleWithItsAttempts() async throws {
        try await each { b in
            let (_, p) = try await self.seeded(b); try await b.recordAttempts(p.map { self.attempt($0.id) })
            try await b.deletePuzzle(p[0].id)
            let lib = try await b.load(); XCTAssertEqual(lib.puzzles.map(\.id), [p[1].id]); XCTAssertEqual(lib.attempts.map(\.puzzleId), [p[1].id])
        }
    }
    func testDeletesACollectionWithPuzzlesAttemptsAndRun() async throws {
        try await each { b in
            let (c, p) = try await self.seeded(b), (kept, keep) = try await self.seeded(b, 1)
            let r = self.run(c.id, p.map(\.id)); try await b.saveRun(r); try await b.saveRun(self.run("all", [keep[0].id]))
            try await b.recordAttempts([self.attempt(p[0].id, runId: r.id), self.attempt(keep[0].id)])
            try await b.deleteCollection(c.id)
            let lib = try await b.load(); XCTAssertEqual(lib.collections.map(\.id), [kept.id])
            XCTAssertEqual(lib.puzzles.map(\.id), [keep[0].id]); XCTAssertEqual(lib.attempts.map(\.puzzleId), [keep[0].id])
            XCTAssertEqual(lib.runs.map(\.scope), ["all"])
        }
    }
    func testStoresAnAttemptUploadedTwiceOnce() async throws {
        try await each { b in
            let (_, p) = try await self.seeded(b, 1); let a = self.attempt(p[0].id); var changed = a; changed.result = .failed
            try await b.recordAttempts([a]); try await b.recordAttempts([a, changed])
            let lib = try await b.load(); XCTAssertEqual(lib.attempts, [a])
        }
    }
    func testDropsDeletedPuzzleAttemptsAndUnlinksDeletedRuns() async throws {
        try await each { b in
            let (_, p) = try await self.seeded(b), r = self.run("all", [])
            try await b.deletePuzzle(p[0].id); try await b.recordAttempts(p.map { self.attempt($0.id, runId: r.id) })
            let lib = try await b.load(); XCTAssertEqual(lib.attempts.count, 1); XCTAssertEqual(lib.attempts[0].puzzleId, p[1].id); XCTAssertNil(lib.attempts[0].runId)
        }
    }
    func testKeepsTheNewestRunPerScope() async throws {
        try await each { b in
            let (c, p) = try await self.seeded(b, 1)
            let first = self.run(c.id, [p[0].id], 1000), second = self.run(c.id, [p[0].id], 2000), stale = self.run(c.id, [p[0].id], 1500)
            try await b.saveRun(first); try await b.recordAttempts([self.attempt(p[0].id, runId: first.id)])
            try await b.saveRun(second); try await b.saveRun(stale); try await b.saveRun(second)
            let lib = try await b.load(); XCTAssertEqual(lib.runs, [second]); XCTAssertNil(lib.attempts[0].runId)
        }
    }
    func testKeepsRunsInDifferentScopesSideBySide() async throws {
        try await each { b in
            let (c, p) = try await self.seeded(b, 1)
            for scope in [c.id, "all", "review"] { try await b.saveRun(self.run(scope, [p[0].id])) }
            let lib = try await b.load(); XCTAssertEqual(lib.runs.count, 3)
        }
    }
    func testDeletesARunKeepingItsAttempts() async throws {
        try await each { b in
            let (_, p) = try await self.seeded(b, 1), r = self.run("all", [])
            try await b.saveRun(r); try await b.recordAttempts([self.attempt(p[0].id, runId: r.id)]); try await b.deleteRun(r.id)
            let lib = try await b.load(); XCTAssertEqual(lib.runs, []); XCTAssertNil(lib.attempts[0].runId)
        }
    }
    func testResetsProgressKeepingTheLibrary() async throws {
        try await each { b in
            let (_, p) = try await self.seeded(b), r = self.run("all", p.map(\.id))
            try await b.saveRun(r); try await b.recordAttempts(p.map { self.attempt($0.id, runId: r.id) }); try await b.resetProgress()
            let lib = try await b.load(); XCTAssertEqual(lib.attempts, []); XCTAssertEqual(lib.runs, [])
            XCTAssertEqual(lib.puzzles.count, 2); XCTAssertEqual(lib.collections.count, 1)
        }
    }
    func testStoresAndLoadsGameCollectionsAndGames() async throws {
        try await each { b in
            let (c, games) = try await self.seededGames(b, 1)
            try await b.addGames([NewGame(id: newID(), collectionId: c.id, position: 1, pgn: "*", orientation: .black)])
            let lib = try await b.load(); XCTAssertEqual(lib.gameCollections, [c]); XCTAssertEqual(lib.games.count, 2)
            XCTAssertEqual(lib.games[0].id, games[0].id); XCTAssertEqual(lib.games[0].pgn, games[0].pgn)
            XCTAssertEqual(lib.games[1].orientation, .black); XCTAssertEqual(lib.collections, [])
        }
    }
    func testUpdatesGameTextAndOrientation() async throws {
        try await each { b in
            let (_, games) = try await self.seededGames(b, 1)
            try await b.updateGame(games[0].id, GameChanges(pgn: "1. d4 *\n")); try await b.updateGame(games[0].id, GameChanges(orientation: .black))
            let lib = try await b.load(); XCTAssertEqual(lib.games[0].pgn, "1. d4 *\n"); XCTAssertEqual(lib.games[0].orientation, .black)
        }
    }
    func testReordersGamesAndMovesThemToAnotherCollection() async throws {
        try await each { b in
            let (a, g) = try await self.seededGames(b)
            let c = GameCollection(id: newID(), name: "Endgames", createdAt: 1234); try await b.createGameCollections([c])
            try await b.placeGames([GamePlacement(id: g[0].id, collectionId: a.id, position: 1), GamePlacement(id: g[1].id, collectionId: c.id, position: 0)])
            let lib = try await b.load()
            XCTAssertEqual(lib.games.first { $0.id == g[0].id }?.position, 1)
            XCTAssertEqual(lib.games.first { $0.id == g[1].id }?.collectionId, c.id)
        }
    }
    func testRefusesAGameInAMissingCollection() async throws {
        try await each { b in
            do { try await b.addGames([NewGame(id: newID(), collectionId: newID(), position: 0, pgn: "*", orientation: .white)]); XCTFail("Accepted missing collection") }
            catch {}
        }
    }
    func testRenamesDeletesGamesAndDeletesACollectionWithItsGames() async throws {
        try await each { b in
            let (c, g) = try await self.seededGames(b, 3), (kept, keep) = try await self.seededGames(b, 1)
            try await b.renameGameCollection(c.id, "Renamed"); try await b.deleteGames([g[0].id])
            var lib = try await b.load(); XCTAssertEqual(lib.gameCollections.first { $0.id == c.id }?.name, "Renamed"); XCTAssertEqual(lib.games.count, 3)
            try await b.deleteGameCollection(c.id); lib = try await b.load()
            XCTAssertEqual(lib.gameCollections.map(\.id), [kept.id]); XCTAssertEqual(lib.games.map(\.id), [keep[0].id])
        }
    }
}
