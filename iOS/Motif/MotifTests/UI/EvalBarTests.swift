import XCTest
@testable import Motif

@MainActor final class EvalBarTests: XCTestCase {
    private let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    private func eval(_ score: Score, depth: Int = 18) -> Evaluation { Evaluation(fen: start, depth: depth, score: score, final: false) }

    func testFillFollowsTheWinChanceCurveAndKeepsBothSidesVisible() {
        XCTAssertEqual(EvalBar.whiteShare(nil), 0.5)
        XCTAssertEqual(EvalBar.whiteShare(eval(.cp(0))), 0.5)
        XCTAssertEqual(EvalBar.whiteShare(eval(.cp(60))), 0.555, accuracy: 0.001)
        XCTAssertEqual(EvalBar.whiteShare(eval(.cp(5000))), 0.98)
        XCTAssertEqual(EvalBar.whiteShare(eval(.cp(-5000))), 0.02)
        XCTAssertEqual(EvalBar.whiteShare(eval(.mate(3))), 1)
        XCTAssertEqual(EvalBar.whiteShare(eval(.mate(-3))), 0)
    }

    func testLabelAndSpokenValue() {
        XCTAssertEqual(EvalBar.label(eval(.cp(-60))), "0.6")
        XCTAssertEqual(EvalBar.label(eval(.mate(-3))), "M3")
        XCTAssertEqual(EvalBar.leader(eval(.cp(-60))), .black)
        XCTAssertEqual(EvalBar.spoken(nil), "Analysing")
        XCTAssertEqual(EvalBar.spoken(eval(.cp(60))), "White is better by 0.6, depth 18")
        XCTAssertEqual(EvalBar.spoken(eval(.cp(-4))), "Equal")
        XCTAssertEqual(EvalBar.spoken(eval(.mate(-3))), "Black mates in 3")
    }
}
