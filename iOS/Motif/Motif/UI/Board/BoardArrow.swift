import Foundation

/// An arrow drawn over the board: own side solid blue, their side dashed orange (§4).
struct BoardArrow: Hashable, Sendable {
    enum Side: Hashable, Sendable { case own, theirs }
    var from: String
    var to: String
    var side: Side
}
