import Foundation

/// A mark the target step puts on a square: a colour on a piece or an empty king-zone square,
/// or a dot on an empty square (king-zone and fork squares look the same, as
/// `ScanGrader.gradeTargets` grades them).
enum ScanTargetMark: Equatable, Sendable {
    case red, orange, dot

    /// What a square can be marked: a piece only red or orange; an empty square next to a king
    /// red, orange or a dot (coloured by its count, AdviceCabinet's rule); any other empty square
    /// only a dot (a fork or check square).
    enum Square: Equatable, Sendable {
        case piece, kingZone, empty

        /// The square as it stands on the board.
        init(_ square: String, fen: String) {
            if Board.pieceAt(fen, square) != nil { self = .piece }
            else { self = ScanImport.nextToAKing(square, fen) ? .kingZone : .empty }
        }
    }

    /// A tap goes red → orange → … → clear, red first as the scan looks for red first
    /// (playtest 3): a piece red → orange → clear; a king-zone square red → orange → dot →
    /// clear; any other empty square straight to dot, then clear.
    static func next(after mark: ScanTargetMark?, on square: Square) -> ScanTargetMark? {
        switch (mark, square) {
        case (nil, .empty): return .dot
        case (nil, _): return .red
        case (.red, _): return .orange
        case (.orange, .kingZone): return .dot
        case (.orange, _), (.dot, _): return nil
        }
    }
}
