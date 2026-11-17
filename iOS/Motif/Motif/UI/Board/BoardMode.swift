import Foundation

/// What a tap or a drag on the board does (Scan plan §4). Only `.play` moves pieces; every
/// other mode hands the squares to the caller and never moves one. One meaning per gesture
/// per step, and every drag has a tap that does the same.
enum BoardMode: Equatable, Sendable {
    /// Select and move pieces through `BoardInteraction`: every board before Scan Training.
    case play
    /// Taps only: each tap calls `onSquare`. Pieces can't be selected or dragged.
    case markSquares
    /// A tap calls `onSquare`; a drag calls `onSquares` once at the end with every square it
    /// crossed, in order, the same as tapping each one.
    case markTargets
    /// A drag from a piece, or a tap on a piece then on a square, calls `onArrow(from, to)`; a
    /// tap on an arrow's shaft calls `onArrowTap` with its index. Nothing moves.
    case drawArrows
}
