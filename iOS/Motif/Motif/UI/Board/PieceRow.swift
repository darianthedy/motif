import SwiftUI

/// Pickers in the layout, not over the board (decision 17, F12): a row of 56 pt buttons
/// under the board when stacked, at the top of the column beside it. Promotion in the
/// Analysis view and the session, the missing piece in the session. Each button is titled
/// with its piece for VoiceOver and keeps the `choose-*` identifier.
struct PieceRow: View {
    let title: String
    let pieces: [PieceType]
    let color: Side
    let choose: (PieceType) -> Void
    let cancel: () -> Void
    static let size: CGFloat = 56
    static let promotion: [PieceType] = [.queen, .rook, .bishop, .knight]
    static let placement: [PieceType] = [.queen, .rook, .bishop, .knight, .pawn]
    init(title: String = "Promote To", pieces: [PieceType] = PieceRow.promotion, color: Side,
         choose: @escaping (PieceType) -> Void, cancel: @escaping () -> Void) {
        self.title = title; self.pieces = pieces; self.color = color; self.choose = choose; self.cancel = cancel
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).font(.subheadline)
                    .frame(minHeight: 44).accessibilityIdentifier("picker-cancel")
            }
            HStack(spacing: 8) {
                ForEach(pieces, id: \.self) { piece in
                    Button { choose(piece) } label: {
                        Label { Text(piece.name) } icon: { PieceImage(type: piece, color: color).padding(6) }
                            .labelStyle(.iconOnly)
                            .frame(width: Self.size, height: Self.size)
                            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                            .contentShape(.rect(cornerRadius: 12))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(piece.name).accessibilityIdentifier("choose-" + piece.rawValue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}
