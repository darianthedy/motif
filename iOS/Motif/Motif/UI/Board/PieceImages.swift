import SwiftUI

extension PieceType {
    var name: String {
        switch self { case .queen: "Queen"; case .rook: "Rook"; case .bishop: "Bishop"; case .knight: "Knight"; case .pawn: "Pawn"; case .king: "King" }
    }
}
struct PieceImage: View {
    let type: PieceType
    let color: Side
    var body: some View {
        Image(color.rawValue + type.rawValue.uppercased()).resizable().scaledToFit().accessibilityHidden(true)
    }
}
