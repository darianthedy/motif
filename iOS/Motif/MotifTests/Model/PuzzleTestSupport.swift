import XCTest
@testable import Motif

let puzzleMateFEN = "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"
let missingPieceFEN = "6rk/6pp/8/1p1b4/p7/3P4/PPP5/1K5R b - - 0 1"
let missingKnight = Placement(color: .white, type: .knight, square: "g6")

func testMove(_ text: String) -> Uci { try! uci(text) }
func testContent(_ lines: [[String]], fen: String = puzzleMateFEN,
                 addPiece: Placement? = nil, comment: String? = nil) -> PuzzleContent {
    PuzzleContent(fen: fen, solutions: lines.map { $0.map(testMove) }, addPiece: addPiece, comment: comment)
}
func testPuzzle(_ lines: [[String]] = [], fen: String = puzzleMateFEN,
                addPiece: Placement? = nil) -> Puzzle {
    Puzzle(content: testContent(lines, fen: fen, addPiece: addPiece),
           id: "p1", collectionId: "c1", position: 0, addedAt: 0)
}

func loadPuzzleFixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    let bundle = Bundle(for: RunnerTests.self)
    let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        ?? bundle.url(forResource: name, withExtension: "json"))
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}

struct ImportFixture: Decodable {
    struct Case: Decodable {
        let name: String
        let text: String
        let expected: ImportResult
    }
    let version: Int
    let cases: [Case]
}

func importEntry(_ fields: String, collection: String? = nil) -> ImportResult {
    let name = collection.map { #""collection": "\#($0)","# } ?? ""
    return importJson("{ \(name) \"puzzles\": [ \(fields) ] }")
}
func importedPuzzles(_ result: ImportResult) -> [PuzzleContent] {
    result.groups.flatMap(\.puzzles)
}

/// The same UInt32 LCG as session.test.ts; wrapping arithmetic is deliberate.
func testSeeded(_ seed: UInt32) -> () -> Double {
    var state = seed
    return {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / 4_294_967_296
    }
}
func testIds(_ n: Int) -> [String] { (0..<n).map { "p\($0)" } }
