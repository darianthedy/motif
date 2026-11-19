import Foundation

/// A mark the target step puts on a square: a colour on a piece or an empty king-zone square,
/// or a dot on an empty square (king-zone and fork squares look the same, as
/// `ScanGrader.gradeTargets` grades them).
enum ScanTargetMark: Equatable, Sendable {
    case red, orange, dot

    /// What a tapped square holds, which decides the marks it can take.
    enum Square: Equatable, Sendable {
        /// A piece: red or orange.
        case piece
        /// An empty square next to either king: red or orange by its count (AdviceCabinet's
        /// rule), or a dot.
        case kingZone
        /// Any other empty square: only a dot (a fork or check square).
        case empty
    }

    /// Red first, as the scan looks for red first: a piece goes red → orange → clear, an empty
    /// king-zone square red → orange → dot → clear, and any other empty square dot → clear.
    static func next(after mark: ScanTargetMark?, on square: Square) -> ScanTargetMark? {
        switch (mark, square) {
        case (nil, .empty): return .dot
        case (nil, _): return .red
        case (.red, _): return .orange
        case (.orange, .kingZone): return .dot
        case (.orange, _): return nil
        case (.dot, _): return nil
        }
    }
}
