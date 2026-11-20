import Foundation

/// What a tap or a drag on the board does (Scan plan §4). Only `.play` moves pieces; every
/// other mode hands the squares to the caller and never moves one. One meaning per gesture
/// per step. Every drag has a tap that does the same, except arrows (`.drawArrows`), where
/// a tap marks a target instead.
enum BoardMode: Equatable, Sendable {
    /// Select and move pieces through `BoardInteraction`: every board before Scan Training.
    case play
    /// Taps only: each tap calls `onSquare`. Pieces can't be selected or dragged.
    case markSquares
    /// A tap calls `onSquare`; a drag calls `onSquares` once at the end with every square it
    /// crossed, in order, the same as tapping each one.
    case markTargets
    /// A drag from a piece calls `onArrow(from, to)`; a tap calls `onSquare` (Scan: a target mark).
    /// Arrows have no tap path and no tap-to-delete: they're removed from the list under the
    /// board, or by drawing them again. Nothing moves.
    case drawArrows
}
