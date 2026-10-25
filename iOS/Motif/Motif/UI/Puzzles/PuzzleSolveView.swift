import SwiftUI
struct PuzzleSolveView: View {
    let model: SolveModel
    let continueAction: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BoardView(fen: model.fen, orientation: solverSide(model.puzzle), interactive: model.phase == .solving,
                      highlight: model.marked, shakeKey: model.shakeKey, onMove: model.submit)
            if model.done { ResultCard(model: model, continueAction: continueAction) }
            else { Text(model.hint == nil ? "\(solverSide(model.puzzle) == .white ? "White" : "Black") to play" : "Play the highlighted move").foregroundStyle(model.hint == nil ? Color.secondary : .orange) }
        }.sensoryFeedback(.success, trigger: model.phase == .solved)
    }
}
