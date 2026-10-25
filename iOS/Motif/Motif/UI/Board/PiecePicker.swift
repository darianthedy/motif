import SwiftUI
struct PiecePicker: View {
    let title: String
    let choices: [PieceType]
    let color: Side
    let choose: (PieceType) -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.headline)
            HStack(spacing: 8) {
                ForEach(choices, id: \.self) { piece in
                    Button { choose(piece) } label: {
                        VStack { PieceImage(type: piece, color: color).frame(width: 44, height: 44); Text(piece.name).font(.caption) }
                    }.accessibilityIdentifier("choose-" + piece.rawValue).accessibilityLabel(piece.name)
                }
            }
            Button("Cancel", action: cancel).accessibilityIdentifier("picker-cancel")
        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(8)
    }
}
