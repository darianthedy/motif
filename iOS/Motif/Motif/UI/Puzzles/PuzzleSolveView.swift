import SwiftUI
struct PuzzleSolveView: View {
    let model: SolveModel
    var body: some View {
        let side = solverSide(model.puzzle)
        VStack(spacing: 16) {
            BoardView(fen: model.fen, orientation: side, interactive: model.phase == .solving,
                      highlight: model.marked, highlightColor: model.hint == nil ? .blue : .orange,
                      shakeKey: model.shakeKey, onMove: model.submit)
            if !model.done {
                SolvePrompt(side: side, guidance: guidance, warning: model.hint != nil)
            }
        }.sensoryFeedback(.success, trigger: model.phase == .solved)
    }
    private var guidance: String {
        if model.hint != nil { return "Not quite. Play the highlighted move." }
        return model.phase == .replying ? "Opponent is replying…" : "Find the best move."
    }
}

/// The capsule under the board: side to move and one line of guidance.
struct SolvePrompt: View {
    let side: Side
    let guidance: String
    var warning = false
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(side == .white ? Color.white : Color.black)
                .overlay(Circle().stroke(.secondary, lineWidth: 1)).frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(side == .white ? "White to move" : "Black to move").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(guidance).font(.subheadline.weight(.medium)).foregroundStyle(warning ? Color.orange : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }
}
