import SwiftUI
struct MissingPieceSolveView: View {
    let model: SolveModel
    let continueAction: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BoardView(fen: model.fen, orientation: solverSide(model.puzzle), interactive: !model.done,
                      placing: model.done ? nil : model.puzzle.addPiece?.color, highlight: model.marked,
                      shakeKey: model.shakeKey, onPlace: model.submit)
            if model.done { ResultCard(model: model, continueAction: continueAction) }
            else if let hint = model.placementHint { Text("Add the \(hint.type.name.lowercased()) on the highlighted square").foregroundStyle(.orange) }
            else { Text("Add a \(solverSide(model.puzzle) == .white ? "white" : "black") piece").foregroundStyle(.secondary) }
        }.sensoryFeedback(.success, trigger: model.phase == .solved)
    }
}
