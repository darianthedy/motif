import SwiftUI

/// A finished puzzle in the Analysis view, from its start position with the
/// solutions as moves. Nothing is stored unless it is saved as a game.
struct PuzzleAnalysisView: View {
    @Environment(AppState.self) private var app
    let puzzle: Puzzle
    var body: some View {
        let collection = app.store.library?.collections.first { $0.id == puzzle.collectionId }?.name
        // A fixed id and date, so a redraw hands the view the same game rather than a new one.
        let game = Game(id: "puzzle-" + puzzle.id, collectionId: "", position: 0,
                        pgn: writePgn(puzzleGame(puzzle, event: collection)), orientation: solverSide(puzzle), addedAt: 0)
        GameContentView(game: game, app: app, scratch: ScratchAnalysis(title: "Puzzle Analysis", subtitle: collection ?? ""))
    }
}
