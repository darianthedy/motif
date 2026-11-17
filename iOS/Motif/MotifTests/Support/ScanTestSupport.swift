import Foundation
@testable import Motif

/// Two bare kings: few legal moves, and every last move from e1 is a new puzzle.
let scanTestFen = "4k3/8/8/8/8/8/8/4K3 w - - 0 1"

/// A puzzle that passes `ScanImport`: every legal reply scored, `scores`
/// overriding the default 0.
func testScanContent(_ lastMove: String = "e1d1", flagged: Bool = true, quickScan: [String] = ["d7"],
                     scores: [String: Int] = [:], source: String? = nil) -> ScanPuzzleContent {
    let move = Uci.parse(lastMove)!
    let start = Board.applyUci(scanTestFen, move)!
    var moves: [String: Int] = [:]
    for legal in Board.legalUcis(start) { moves[legal.text] = scores[legal.text] ?? 0 }
    let answer = ScanAnswer(flagged: flagged, quickScan: quickScan.map { ScanSquare(square: $0, kind: .attacked) },
                            targets: nil, arrows: nil, moves: moves, bestLine: nil)
    return ScanPuzzleContent(fenBefore: scanTestFen, lastMove: move, answer: answer, version: 1,
                             source: source, sourceId: nil)
}

func testScanPuzzle(_ id: String, _ lastMove: String = "e1d1", addedAt: Int64 = 0) -> ScanPuzzle {
    ScanPuzzle(id: id, content: testScanContent(lastMove), addedAt: addedAt)
}

func testScanAttempt(_ id: String, _ puzzleId: String, _ result: AttemptResult = .solved,
                     runId: String? = nil, playedAt: Int64 = 1) -> ScanAttempt {
    ScanAttempt(id: id, puzzleId: puzzleId, runId: runId, result: result,
                flagCall: result == .skipped ? nil : true, detail: ScanAttemptDetail(), playedAt: playedAt)
}

func testScanRun(_ scope: String = SCOPE_ALL, _ time: Int64 = 5, queue: [String] = ["s1"]) -> Run {
    Run(id: "scan-\(scope)-\(time)", scope: scope, mode: scope == SCOPE_REVIEW ? .reviewMistakes : .randomGlobal,
        queue: queue, startedAt: time)
}
