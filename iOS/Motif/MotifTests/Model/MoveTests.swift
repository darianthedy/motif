import XCTest
@testable import Motif

final class MoveTests: XCTestCase {
    func testMakeMoveValidatesAndPreservesPromotion() throws {
        XCTAssertEqual(try makeMove("e2", "e4").text, "e2e4")
        XCTAssertEqual(try makeMove("a7", "a8", .knight).text, "a7a8n")
        XCTAssertThrowsError(try makeMove("z2", "e4"))
        XCTAssertThrowsError(try uci("e2-e4"))
    }

    func testUciEncodesAsAStringAcrossDataBoundaries() throws {
        let value = try uci("e2e4")
        XCTAssertEqual(String(data: try JSONEncoder().encode(value), encoding: .utf8), "\"e2e4\"")
        XCTAssertEqual(try JSONDecoder().decode(Uci.self, from: Data("\"e2e4\"".utf8)), value)
    }

    func testInvalidUciCannotEnterThroughDecoding() {
        XCTAssertThrowsError(try JSONDecoder().decode(Uci.self, from: Data("\"bad\"".utf8)))
    }

    func testOnlyAnExplicitQueenPromotionCanBeStripped() throws {
        XCTAssertEqual(stripQueenPromotion(try uci("a7a8q"))?.text, "a7a8")
        for text in ["a7a8", "a7a8n", "a7a8r", "a7a8b"] {
            XCTAssertNil(stripQueenPromotion(try uci(text)))
        }
    }
}
