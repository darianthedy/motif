import SwiftUI
/// A glass card over the dimmed board: “Promote to” or “Add on f6”.
struct PiecePicker: View {
    let title: String
    let choices: [PieceType]
    let color: Side
    let choose: (PieceType) -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.headline)
            HStack(spacing: 8) {
                ForEach(choices, id: \.self) { piece in
                    Button { choose(piece) } label: {
                        VStack(spacing: 2) {
                            PieceImage(type: piece, color: color).frame(width: 44, height: 44)
                            Text(piece.name).font(.caption2).foregroundStyle(.secondary)
                        }.frame(minWidth: 52).padding(.vertical, 6).padding(.horizontal, 4).contentShape(.rect)
                    }.buttonStyle(.plain).background(.fill.tertiary, in: .rect(cornerRadius: 14))
                        .accessibilityIdentifier("choose-" + piece.rawValue).accessibilityLabel(piece.name)
                }
            }
            Button("Cancel", role: .cancel, action: cancel).buttonStyle(.bordered).buttonBorderShape(.capsule).accessibilityIdentifier("picker-cancel")
        }.padding(18).glassEffect(.regular, in: .rect(cornerRadius: 26)).padding(8)
    }
}
