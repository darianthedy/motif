import Foundation

/// A puzzle opened for analysis: its start position, with the answer placed for
/// a missing-piece puzzle, and every solution as moves, the first as the main line.
func puzzleGame(_ puzzle: Puzzle, event: String? = nil) -> ParsedGame {
    let fen = normalizeFen(puzzle.fen)
    var game = newGame(puzzle.addPiece.flatMap { Board.withPiece(fen, $0) } ?? fen)
    game.headers["Event"] = event ?? "Puzzle"
    guard puzzle.addPiece == nil else { return game }
    for line in puzzle.solutions {
        var path: MovePath = []
        for move in line {
            guard let edit = try? playMove(game, path, move) else { break }
            game = edit.game; path = edit.path
        }
    }
    return game
}
