import SwiftUI
/// The move puzzle's board. The session puts it in its `BoardLayout`; the prompt and the
/// promotion row go in the column (decision 17), handed over through `pending`.
struct PuzzleSolveView: View {
    let model: SolveModel
    @Binding var pending: BoardPending?
    var body: some View {
        BoardView(fen: model.fen, orientation: solverSide(model.puzzle), interactive: model.phase == .solving,
                  highlight: model.marked, highlightColor: model.hint == nil ? .blue : .orange,
                  shakeKey: model.shakeKey, onMove: model.submit, pending: $pending)
            .sensoryFeedback(.success, trigger: model.phase == .solved)
            .diagProbe("session.board") { "puzzle \(model.puzzle.id) phase \(model.phase)" }
    }
}

/// The capsule under the board or atop the column: side to move and one line of guidance.
struct SolvePrompt: View {
    let side: Side
    let guidance: String
    var warning = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(side == .white ? Color.white : Color.black)
                .overlay(Circle().stroke(.secondary, lineWidth: 1)).frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(side == .white ? "White to move" : "Black to move").font(.caption.weight(.semibold)).foregroundStyle(.motifSecondary)
                Text(guidance).font(.subheadline.weight(.medium)).foregroundStyle(warning ? Color.orange : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        // A capsule's ends would clip the wrapped lines at accessibility sizes.
        .motifGlass(in: typeSize.isAccessibilitySize ? AnyShape(.rect(cornerRadius: 22)) : AnyShape(.capsule))
        .accessibilityElement(children: .contain)
    }
}
extension SolvePrompt {
    /// The prompt for either kind of puzzle, as the solve views showed it under the board.
    init(model: SolveModel) {
        let side = solverSide(model.puzzle)
        if model.puzzle.addPiece != nil {
            if let hint = model.placementHint {
                self.init(side: side, guidance: "Not quite. Add the \(hint.type.name.lowercased()) on the orange square.", warning: true)
            } else {
                self.init(side: side, guidance: "Tap the square where a piece is missing.")
            }
        } else if model.hint != nil {
            self.init(side: side, guidance: "Not quite. Play the highlighted move.", warning: true)
        } else {
            self.init(side: side, guidance: model.phase == .replying ? "Opponent is replying…" : "Find the best move.")
        }
    }
}
