import ChessKitEngine
import XCTest
@testable import Motif

final class UCITests: XCTestCase {
    private let whiteToMove = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1"
    private let blackToMove = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"

    func testReadsDepthCentipawnsRankAndPv() {
        XCTAssertEqual(UCI.parse("info depth 18 seldepth 25 multipv 1 score cp 34 nodes 1204511 nps 1500000 time 803 pv e2e4 e7e5 g1f3"),
                       .info(depth: 18, score: .cp(34), pv: ["e2e4", "e7e5", "g1f3"], multipv: 1))
        XCTAssertEqual(UCI.parse("info depth 18 seldepth 24 multipv 3 score cp 12 nodes 1204511 pv g1f3 d7d5"),
                       .info(depth: 18, score: .cp(12), pv: ["g1f3", "d7d5"], multipv: 3))
        XCTAssertEqual(UCI.parse("info depth 3 score cp -12 nodes 40"), .info(depth: 3, score: .cp(-12), pv: []))
    }

    func testReadsMateAndNegativeMate() {
        XCTAssertEqual(UCI.parse("info depth 30 score mate 3 pv h5f7"), .info(depth: 30, score: .mate(3), pv: ["h5f7"]))
        XCTAssertEqual(UCI.parse("info depth 30 score mate -2 pv g8h8"), .info(depth: 30, score: .mate(-2), pv: ["g8h8"]))
    }

    func testIgnoresBoundsMissingScoresAndStrings() {
        XCTAssertNil(UCI.parse("info depth 20 seldepth 28 score cp 51 lowerbound nodes 9 pv d2d4"))
        XCTAssertNil(UCI.parse("info depth 20 seldepth 28 score cp 40 upperbound nodes 9 pv d2d4"))
        XCTAssertNil(UCI.parse("info depth 20 currmove e2e4 currmovenumber 1"))
        XCTAssertNil(UCI.parse("info score cp 20 pv e2e4"))
        XCTAssertNil(UCI.parse("info string NNUE evaluation using nn-1111cefa1111.nnue"))
        XCTAssertNil(UCI.parse("readyok"))
        XCTAssertNil(UCI.parse(""))
    }

    func testReadsBestmove() {
        XCTAssertEqual(UCI.parse("bestmove e2e4 ponder e7e5"), .bestmove("e2e4"))
        XCTAssertEqual(UCI.parse("bestmove (none)"), .bestmove("(none)"))
    }

    func testFlipsScoresToWhitesPointOfViewWhenBlackIsToMove() {
        XCTAssertEqual(UCI.parse("info depth 10 score cp 34 pv e2e4", fen: whiteToMove), .info(depth: 10, score: .cp(34), pv: ["e2e4"]))
        XCTAssertEqual(UCI.parse("info depth 10 score cp 34 pv e7e5", fen: blackToMove), .info(depth: 10, score: .cp(-34), pv: ["e7e5"]))
        XCTAssertEqual(UCI.parse("info depth 10 score mate -2 pv g8h8", fen: blackToMove), .info(depth: 10, score: .mate(2), pv: ["g8h8"]))
        XCTAssertEqual(UCI.parse("bestmove e7e5", fen: blackToMove), .bestmove("e7e5"))
    }

    func testFinishedMateBelongsToTheSideNotToMove() {
        XCTAssertEqual(Evaluation(fen: blackToMove, depth: 0, score: .mate(0), final: true).winner, .white)
        XCTAssertEqual(Evaluation(fen: whiteToMove, depth: 9, score: .mate(-4), final: false).winner, .black)
        XCTAssertNil(Evaluation(fen: whiteToMove, depth: 9, score: .cp(500), final: false).winner)
    }

    func testAdapterSpeaksChessKitEngineCommandsAndLines() {
        XCTAssertEqual(StockfishEngine.command("stop"), .stop)
        XCTAssertEqual(StockfishEngine.command("position fen \(blackToMove)"), .position(.fen(blackToMove)))
        XCTAssertEqual(StockfishEngine.command("go depth 22 movetime 20000"), .go(depth: 22, movetime: 20000))
        XCTAssertEqual(StockfishEngine.command("setoption name Hash value 128"), .setoption(id: "Hash", value: "128"))
        XCTAssertEqual(StockfishEngine.command("setoption name MultiPV value 3"), .setoption(id: "MultiPV", value: "3"))
        XCTAssertEqual(StockfishEngine.line(for: .bestmove(move: "e2e4", ponder: nil)), "bestmove e2e4")
    }
}
