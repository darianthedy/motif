import Foundation

/// What a tap or a drag on the board does (Scan plan §4). Only `.play` moves pieces; every
/// other mode hands the square to the caller and never moves one. One meaning per gesture
/// per step. `.markTargets` and `.drawArrows` come with S07.
enum BoardMode: Equatable, Sendable {
    /// Select and move pieces through `BoardInteraction`: every board before Scan Training.
    case play
    /// Taps only: each tap calls `onSquare`. Pieces can't be selected or dragged.
    case markSquares
}
