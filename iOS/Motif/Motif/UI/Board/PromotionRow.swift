import SwiftUI

/// Promotion in the layout, not over the board (decision 17, F12): four 56 pt buttons
/// under the board when stacked, at the top of the column beside it. Each is titled
/// with its piece for VoiceOver and keeps the picker's `choose-*` identifier.
struct PromotionRow: View {
    let color: Side
    let choose: (PieceType) -> Void
    let cancel: () -> Void
    static let size: CGFloat = 56
    private static let pieces: [PieceType] = [.queen, .rook, .bishop, .knight]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Promote To").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).font(.subheadline)
                    .frame(minHeight: 44).accessibilityIdentifier("picker-cancel")
            }
            HStack(spacing: 8) {
                ForEach(Self.pieces, id: \.self) { piece in
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
        .accessibilityElement(children: .contain).accessibilityLabel("Promote to")
    }
}
