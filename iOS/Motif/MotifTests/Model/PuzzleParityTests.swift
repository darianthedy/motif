import XCTest
@testable import Motif

final class PuzzleParityTests: XCTestCase {
    private struct Keys: Decodable {
        struct Case: Decodable {
            let input: PuzzleContent
            let key: String
            let normalizedFen: String
            let side: Side
        }
        struct PlacementCase: Decodable {
            let text: String
            let parsed: Placement?
            let canonical: String?
        }
        let version: Int
        let cases: [Case]
        let placements: [PlacementCase]
    }
    private struct Model: Decodable {
        struct Session: Decodable {
            let seed: UInt32
            let ids: [String]
            let recent: [String]
            let queues: [String: [String]]
            let global: [String]
        }
        struct Runner: Decodable {
            struct Step: Decodable {
                struct Outcome: Decodable {
                    let kind: String
                    let reply: Uci?
                    let finished: Bool?
                }
                let move: Uci
                let outcome: Outcome
                let hint: Uci?
                let accepted: [Uci]
                let misses: [Miss]
                let wrongAtThisPly: Int
                let complete: Bool
                let hinted: Bool
                let result: PuzzleResult
            }
            let puzzle: Puzzle
            let moves: [Step]
        }
        struct LibraryCase: Decodable {
            struct Plan: Decodable { let puzzles: [NewPuzzle]; let added: Int }
            let input: Library
            let incoming: [PuzzleContent]
            let collections: [Collection]
            let puzzles: [Puzzle]
            let all: [Puzzle]
            let run: Run
            let progress: RunProgress
            let resumable: Bool
            let absentResumable: Bool
            let plan: Plan
            let records: [String: PuzzleRecord]
            let recent: [String]
            let emptyProgress: RunProgress
        }
        struct ResumeCase: Decodable {
            let input: Library
            let expected: Bool
        }
        let version: Int
        let sessions: [Session]
        let runners: [Runner]
        let library: LibraryCase
        let emptyIdResume: ResumeCase
    }

    func testContentKeysAreByteIdenticalToTheWeb() throws {
        let fixture = try loadPuzzleFixture("content-keys", as: Keys.self)
        XCTAssertEqual(fixture.version, 1)
        for item in fixture.cases {
            XCTAssertEqual(Array(contentKey(item.input).utf8), Array(item.key.utf8), item.key)
            XCTAssertEqual(normalizeFen(item.input.fen), item.normalizedFen)
            XCTAssertEqual(solverSide(item.input), item.side)
        }
    }
    func testPlacementParsingAndCanonicalTextMatchTheWeb() throws {
        let fixture = try loadPuzzleFixture("content-keys", as: Keys.self)
        for item in fixture.placements {
            let parsed = parsePlacement(item.text)
            XCTAssertEqual(parsed, item.parsed, item.text)
            XCTAssertEqual(parsed.map(placementText), item.canonical, item.text)
        }
    }
    func testCompleteImportsMatchTheWebIncludingRejectionsAndDedupeOrder() throws {
        let fixture = try loadPuzzleFixture("import", as: ImportFixture.self)
        XCTAssertEqual(fixture.version, 1)
        for item in fixture.cases {
            var actual = importJson(item.text)
            var expected = item.expected
            // JSON parser diagnostics differ by platform. Preserve/test the
            // exact shared prefix and index, compare every other reason verbatim.
            for index in expected.rejected.indices where expected.rejected[index].index == -1 {
                XCTAssertTrue(actual.rejected.first?.reason.hasPrefix("Not valid JSON: ") == true, item.name)
                expected.rejected[index].reason = "Not valid JSON"
            }
            for index in actual.rejected.indices where actual.rejected[index].index == -1 {
                actual.rejected[index].reason = "Not valid JSON"
            }
            XCTAssertEqual(actual, expected, item.name)
        }
    }
    func testSeededSessionOrdersMatchTheWebExactly() throws {
        let fixture = try loadPuzzleFixture("puzzle-model", as: Model.self)
        XCTAssertEqual(fixture.version, 1)
        for item in fixture.sessions {
            for mode in SessionMode.allCases {
                XCTAssertEqual(makeQueue(mode, item.ids, testSeeded(item.seed)), item.queues[mode.rawValue],
                               "\(mode) seed \(item.seed) count \(item.ids.count)")
            }
            XCTAssertEqual(orderForGlobalDraw(item.ids, item.recent, testSeeded(item.seed)), item.global)
        }
    }
    func testRunnerTracesMatchTheWeb() throws {
        let fixture = try loadPuzzleFixture("puzzle-model", as: Model.self)
        for item in fixture.runners {
            let runner = PuzzleRunner(item.puzzle)
            for step in item.moves {
                let expected: MoveOutcome = step.outcome.kind == "wrong" ? .wrong
                    : .correct(reply: step.outcome.reply, finished: try XCTUnwrap(step.outcome.finished))
                XCTAssertEqual(runner.submit(step.move), expected, step.move.text)
                XCTAssertEqual(runner.revealHint(), step.hint)
                XCTAssertEqual(runner.accepted, step.accepted)
                XCTAssertEqual(runner.misses, step.misses)
                XCTAssertEqual(runner.wrongAtThisPly, step.wrongAtThisPly)
                XCTAssertEqual(runner.complete, step.complete)
                XCTAssertEqual(runner.hinted, step.hinted)
                XCTAssertEqual(runner.result, step.result)
            }
        }
    }
    func testLibraryOrderingResumeAndDerivationsMatchTheWeb() throws {
        let fixture = try loadPuzzleFixture("puzzle-model", as: Model.self)
        let item = fixture.library
        XCTAssertEqual(collectionsOf(item.input), item.collections)
        XCTAssertEqual(puzzlesIn(item.input, "c"), item.puzzles)
        XCTAssertEqual(allPuzzles(item.input), item.all)
        XCTAssertEqual(runIn(item.input, "c"), item.run)
        XCTAssertNil(runIn(item.input, "absent"))
        XCTAssertEqual(progressOf(item.input, item.run), item.progress)
        XCTAssertEqual(resumable(item.input, "c"), item.resumable)
        XCTAssertEqual(resumable(item.input, "absent"), item.absentResumable)
        let plan = planImport(puzzlesIn(item.input, "c"), item.incoming, "c")
        XCTAssertEqual(plan.puzzles, item.plan.puzzles)
        XCTAssertEqual(plan.added, item.plan.added)
        XCTAssertEqual(puzzleRecords(item.input.attempts), item.records)
        XCTAssertEqual(recentIds(item.input.attempts), item.recent)
        var empty = item.run
        empty.queue = []
        XCTAssertEqual(runProgress(empty, item.input.attempts, []), item.emptyProgress)
        XCTAssertEqual(resumable(fixture.emptyIdResume.input, "c"), fixture.emptyIdResume.expected)
    }
}
