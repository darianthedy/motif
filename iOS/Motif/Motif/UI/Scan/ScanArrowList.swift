import SwiftUI

/// The arrows drawn so far, under or beside the board, each a button that deletes it (Scan plan
/// §4). The way to delete an arrow without hitting its shaft: with VoiceOver, Switch Control, or
/// when two arrows overlap.
struct ScanArrowList: View {
    let arrows: [BoardArrow]
    /// The board, for the pieces' names.
    let fen: String
    let remove: (Int) -> Void
    var body: some View {
        if !arrows.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(Array(arrows.enumerated()), id: \.element) { index, arrow in
                    Button { remove(index) } label: {
                        Label(text(arrow), systemImage: "xmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                    // Small to look at, 44 pt to touch.
                    .frame(minHeight: 44).contentShape(.rect)
                    .tint(arrow.side == .own ? BoardPalette.arrowOwn : BoardPalette.arrowTheirs)
                    .accessibilityLabel("Arrow \(arrow.from) to \(arrow.to), \(arrow.side == .own ? "yours" : "theirs")")
                    .accessibilityHint("Deletes the arrow.")
                    .accessibilityIdentifier("scan-arrow-\(arrow.line)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Arrows")
        }
    }
    /// "Nf3 → g5": the piece's letter, as in move notation, and the squares.
    private func text(_ arrow: BoardArrow) -> String {
        let piece = Board.pieceAt(fen, arrow.from).map { $0.type == .pawn ? "" : $0.type.rawValue.uppercased() } ?? ""
        return "\(piece)\(arrow.from) → \(arrow.to)"
    }
}
