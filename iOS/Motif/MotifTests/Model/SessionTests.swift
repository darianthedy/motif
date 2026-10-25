import XCTest
@testable import Motif

/// One test for every session.test.ts case (4).
final class SessionTests: XCTestCase {
    func testPreservesInsertionOrderInOrderedMode() {
        XCTAssertEqual(makeQueue(.ordered, testIds(5), testSeeded(1)), testIds(5))
    }
    func testShufflesIntoAPermutationWithNoRepeats() {
        let list = testIds(50)
        let queue = makeQueue(.randomInCollection, list, testSeeded(42))
        XCTAssertEqual(queue.count, 50)
        XCTAssertEqual(Set(queue), Set(list))
        XCTAssertNotEqual(queue, list)
    }
    func testPutsRecentlySeenPuzzlesLastWithoutExcludingThem() {
        let order = orderForGlobalDraw(testIds(6), ["p0", "p1"], testSeeded(5))
        XCTAssertEqual(order.count, 6)
        XCTAssertEqual(Set(order), Set(testIds(6)))
        XCTAssertEqual(order.suffix(2).sorted(), ["p0", "p1"])
    }
    func testStillReturnsEverythingWhenTheWholeLibraryIsRecent() {
        XCTAssertEqual(Set(orderForGlobalDraw(testIds(3), testIds(3), testSeeded(5))), Set(testIds(3)))
    }
}
