import SwiftUI
struct MissingPieceSolveView: View {
    let model: SolveModel
    var body: some View {
        let side = solverSide(model.puzzle)
        VStack(spacing: 16) {
            BoardView(fen: model.fen, orientation: side, interactive: !model.done,
                      placing: model.done ? nil : model.puzzle.addPiece?.color, highlight: model.marked,
                      highlightColor: model.placementHint != nil && !model.done ? .orange : .blue,
                      shakeKey: model.shakeKey, onPlace: model.submit)
            if !model.done {
                if let hint = model.placementHint {
                    SolvePrompt(side: side, guidance: "Not quite. Add the \(hint.type.name.lowercased()) on the orange square.", warning: true)
                } else {
                    SolvePrompt(side: side, guidance: "Tap the square where a piece is missing.")
                }
            }
        }.sensoryFeedback(.success, trigger: model.phase == .solved)
    }
}
