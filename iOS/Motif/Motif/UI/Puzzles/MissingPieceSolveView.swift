import SwiftUI
/// The missing-piece puzzle's board. A tapped empty square is handed over through
/// `pending`, and the session's `PieceRow` asks for the piece (decision 17).
struct MissingPieceSolveView: View {
    let model: SolveModel
    @Binding var pending: BoardPending?
    var body: some View {
        BoardView(fen: model.fen, orientation: solverSide(model.puzzle), interactive: !model.done,
                  placing: model.done ? nil : model.puzzle.addPiece?.color, highlight: model.marked,
                  highlightColor: model.placementHint != nil && !model.done ? .orange : .blue,
                  shakeKey: model.shakeKey, onPlace: model.submit, pending: $pending)
            .sensoryFeedback(.success, trigger: model.phase == .solved)
            .diagProbe("session.board") { "puzzle \(model.puzzle.id) phase \(model.phase)" }
    }
}
