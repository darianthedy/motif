import Foundation

/// An arrow drawn over the board: own side solid blue, their side dashed orange (§4). Graded
/// arrows also change shape, so the result never rests on colour alone.
struct BoardArrow: Hashable, Sendable {
    enum Side: Hashable, Sendable { case own, theirs }
    enum Style: Hashable, Sendable {
        /// As drawn, or the best move after a failed one.
        case drawn
        /// Drawn and in the answer: a `checkmark` badge on the shaft.
        case correct
        /// In the answer, not drawn: an outline only, no fill.
        case missed
    }
    var from: String
    var to: String
    var side: Side
    var style = Style.drawn

    /// From + to squares ("f3g5"), as `ScanArrow.line`.
    var line: String { from + to }
}
