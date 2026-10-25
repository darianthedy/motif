import XCTest
@testable import Motif

/// One test for every library.test.ts case (2).
final class LibraryTests: XCTestCase {
    func testNumbersANewCollectionInFileOrder() {
        let plan = planImport([], [testContent([["a1a8"]]), testContent([["a1a7"]])], "c1")
        XCTAssertEqual(plan.puzzles.map(\.collectionId), ["c1", "c1"])
        XCTAssertEqual(plan.puzzles.map(\.position), [0, 1])
        XCTAssertEqual(plan.added, 2)
    }
    func testKeepsThePlaceOfAnExistingPuzzleAndAppendsTheRest() {
        let existing = [
            Puzzle(content: testContent([["a1a7"]]), id: "x", collectionId: "c1", position: 0, addedAt: 0),
            Puzzle(content: testContent([["a1a6"]]), id: "y", collectionId: "c1", position: 4, addedAt: 0),
        ]
        let plan = planImport(existing, [testContent([["a1a8"]]), testContent([["a1a6"]], comment: "edited")], "c1")
        XCTAssertEqual(plan.puzzles.map { $0.solutions[0][0] }, ["a1a8", "a1a6"].map(testMove))
        XCTAssertEqual(plan.puzzles.map(\.position), [5, 4])
        XCTAssertEqual(plan.puzzles.map(\.comment), [nil, "edited"])
        XCTAssertEqual(plan.added, 1)
    }
}
