// These board-facing value types are needed in P02. P03 ports the puzzle model.
enum Side: String, Codable, CaseIterable, Sendable {
    case white = "w", black = "b"
    var opposite: Side { self == .white ? .black : .white }
}

enum PieceType: String, Codable, CaseIterable, Sendable {
    case pawn = "p", knight = "n", bishop = "b", rook = "r", queen = "q", king = "k"
}

/// A piece and its square, the answer to a missing-piece puzzle. It is not a
/// move: nothing travels from anywhere, so it must not be squeezed into UCI.
struct Placement: Hashable, Codable, Sendable {
    var color: Side
    var type: PieceType
    var square: String
}
