import Foundation

/// The words the Scan tab shows for one puzzle (list row, detail), worked out once from the
/// maker's content. Pure, so it is tested without views.
struct ScanPuzzleSummary: Equatable {
    /// `sourceId`, or the puzzle's place in the pool when it has none.
    let number: String
    /// The solver: the side to move after the opponent's last move.
    let solver: Side
    /// "3... Nf6".
    let lastMove: String
    /// "Flag" or "No Flag".
    let call: String
    /// "e4 attacked, c6 undefended", or "Nothing".
    let quickScan: String
    /// The moves scored 0, in SAN: "d3".
    let bestMoves: [String]
    /// "1. d3 d5 2. exd5", or nil without a line.
    let bestLine: String?
    /// A source id like "Velan, 14...f6 (played exf6)" names the move played in the game, often
    /// the answer: the list leaves it out (playtest 4).
    static func hidingPlayedMove(_ id: String) -> String {
        id.replacing(/\s*\(played [^)]*\)/, with: "")
    }
    init(_ puzzle: ScanPuzzle, index: Int) {
        number = puzzle.content.sourceId.map(Self.hidingPlayedMove) ?? "\(index + 1)"
        let start = puzzle.startFen ?? puzzle.fenBefore
        solver = Board.turnOf(start) ?? .white
        let san = Board.sanFor(puzzle.fenBefore, puzzle.lastMove) ?? puzzle.lastMove.text
        lastMove = [moveNumber(puzzle.fenBefore, true), san].compactMap { $0 }.joined(separator: " ")
        let answer = puzzle.answer
        call = answer.flagged ? "Flag" : "No Flag"
        quickScan = answer.quickScan.isEmpty ? "Nothing" : answer.quickScan.map { "\($0.square) \($0.kind.rawValue)" }.joined(separator: ", ")
        bestMoves = answer.moves.filter { $0.value == 0 }.keys.sorted()
            .compactMap { Uci.parse($0).flatMap { Board.sanFor(start, $0) } }
        if let line = answer.bestLine, !line.isEmpty {
            let steps = Board.replayLine(start, line)
            bestLine = steps.enumerated().map { index, step in
                let before = index == 0 ? start : steps[index - 1].fen
                return [moveNumber(before, index == 0), step.san].compactMap { $0 }.joined(separator: " ")
            }.joined(separator: " ")
        } else { bestLine = nil }
    }
}
