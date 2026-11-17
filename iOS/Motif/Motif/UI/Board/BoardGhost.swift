import Foundation

/// A piece shown see-through on a square: the move under final check (S08).
struct BoardGhost: Equatable, Sendable {
    var square: String
    var piece: Board.Piece
}
