import XCTest
@testable import Motif

/// ScanImport over the shared fixtures (`Fixtures/scan/scan-import.json`),
/// which `scripts/scan-check.test.ts` runs too, plus what only Swift stores.
final class ScanImportTests: XCTestCase {
    private struct Case {
        let name: String
        let text: String
        let accepted: [(key: String, flagged: Bool)]
        let rejected: [ImportRejection]
    }

    private func cases() throws -> [Case] {
        let bundle = Bundle(for: ScanImportTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "scan-import", withExtension: "json", subdirectory: "Fixtures/scan")
                ?? bundle.url(forResource: "scan-import", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let raw = try XCTUnwrap(root["cases"] as? [[String: Any]])
        return try raw.map { item in
            let file = try JSONSerialization.data(withJSONObject: try XCTUnwrap(item["file"]), options: .fragmentsAllowed)
            let accepted = (item["accepted"] as? [[String: Any]] ?? []).map {
                (key: $0["key"] as! String, flagged: $0["flagged"] as! Bool)
            }
            let rejected = (item["rejected"] as? [[String: Any]] ?? []).map {
                ImportRejection(index: $0["index"] as! Int, reason: $0["reason"] as! String)
            }
            return Case(name: item["name"] as! String, text: String(decoding: file, as: UTF8.self),
                        accepted: accepted, rejected: rejected)
        }
    }

    func testSharedFixtures() throws {
        let all = try cases()
        XCTAssertGreaterThanOrEqual(all.count, 9)
        for fixture in all {
            let result = ScanImport.read(fixture.text)
            XCTAssertEqual(result.rejected, fixture.rejected, fixture.name)
            XCTAssertEqual(result.puzzles.map(\.contentKey), fixture.accepted.map(\.key), fixture.name)
            XCTAssertEqual(result.puzzles.map(\.answer.flagged), fixture.accepted.map(\.flagged), fixture.name)
        }
    }

    func testReportsAFileThatIsNotJSON() {
        let result = ScanImport.read("{")
        XCTAssertEqual(result.rejected.map(\.index), [-1])
        XCTAssertTrue(result.rejected[0].reason.hasPrefix("Not valid JSON: "))
    }

    func testReadsEveryField() throws {
        let text = #"""
        {"version": 1, "scan": [{
          "fenBefore": "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3",
          "lastMove": "G8F6", "flagged": true,
          "quickScan": [{"square": "e4", "kind": "attacked"}, {"square": "c6", "kind": "undefended"}],
          "targets": {"red": ["f7"], "orange": ["e5"], "kingZone": ["g7"]},
          "arrows": [{"from": "f3", "to": "g5", "side": "own", "kind": "threat"}],
          "moves": \#(movesJSON),
          "bestLine": ["f3g5", "d7d5"], "source": "lichess", "sourceId": 42
        }]}
        """#
        let result = ScanImport.read(text)
        XCTAssertEqual(result.rejected, [])
        let puzzle = try XCTUnwrap(result.puzzles.first)
        XCTAssertEqual(puzzle.lastMove, testMove("g8f6"))
        XCTAssertEqual(puzzle.version, 1)
        XCTAssertEqual(puzzle.source, "lichess")
        XCTAssertEqual(puzzle.sourceId, "42")
        XCTAssertEqual(puzzle.startFen, "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4")
        XCTAssertEqual(puzzle.answer.quickScan, [.init(square: "e4", kind: .attacked), .init(square: "c6", kind: .undefended)])
        XCTAssertEqual(puzzle.answer.targets, ScanTargets(red: ["f7"], orange: ["e5"], kingZone: ["g7"], fork: []))
        XCTAssertEqual(puzzle.answer.arrows, [ScanArrow(from: "f3", to: "g5", side: .own, kind: .threat)])
        XCTAssertEqual(puzzle.answer.bestLine, [testMove("f3g5"), testMove("d7d5")])
        XCTAssertEqual(puzzle.answer.lossCp(testMove("d2d3")), 0)
        XCTAssertEqual(puzzle.answer.lossCp(testMove("c4f7")), 552)
        XCTAssertNil(puzzle.answer.lossCp(testMove("e2e4")))
    }

    /// What the loader does with a row written straight to the database.
    func testAStoredAnswerRoundTripsAndIsCheckedTheSameWay() throws {
        let puzzle = try XCTUnwrap(ScanImport.read(sampleText()).puzzles.first)
        let data = try JSONEncoder().encode(puzzle.answer)
        let decoded = try JSONDecoder().decode(ScanAnswer.self, from: data)
        XCTAssertEqual(decoded, puzzle.answer)
        XCTAssertNil(ScanImport.problem(puzzle))

        var newer = puzzle
        newer.version = 2
        XCTAssertEqual(ScanImport.problem(newer), "Format version 2 is newer than this app understands (1)")
        var gap = puzzle
        gap.answer.moves.removeValue(forKey: "d2d3")
        XCTAssertEqual(ScanImport.problem(gap), "Moves are missing 1 legal move: d2d3")
    }

    func testTheSolversPromotionsAreFourMoves() {
        let fen = "8/1P6/8/8/8/8/6k1/4K3 b - - 0 50"
        let start = Board.applyUci(fen, testMove("g2g3"))!
        XCTAssertEqual(Set(Board.legalUcis(start).map(\.text)).intersection(["b7b8q", "b7b8r", "b7b8b", "b7b8n"]).count, 4)
        XCTAssertEqual(Board.legalUcis("not a fen"), [])
    }

    private var movesJSON: String {
        #"{"d2d3": 0, "f3g5": 12, "d1e2": 24, "b1c3": 29, "d2d4": 32, "c4d5": 36, "c4b5": 43, "e1g1": 43, "h2h3": 51, "c4b3": 101, "c2c3": 108, "c4d3": 118, "a2a3": 120, "a2a4": 124, "b2b3": 151, "c4e2": 159, "c4f1": 174, "h2h4": 186, "b2b4": 187, "g2g3": 188, "b1a3": 201, "h1g1": 221, "g2g4": 225, "e1f1": 231, "e1e2": 246, "h1f1": 265, "f3g1": 277, "f3h4": 340, "f3e5": 504, "c4f7": 552, "c4a6": 724, "f3d4": 753, "c4e6": 826}"#
    }

    private func sampleText() -> String {
        #"{"version": 1, "scan": [{"fenBefore": "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3", "lastMove": "g8f6", "flagged": true, "quickScan": [], "moves": \#(movesJSON)}]}"#
    }
}
