import Foundation

/// A check, capture or threat the full scan should find (format v2).
struct ScanArrow: Hashable, Codable, Sendable {
    enum Side: String, Codable, CaseIterable, Sendable { case own, theirs }
    enum Kind: String, Codable, CaseIterable, Sendable { case check, capture, threat }

    var from: String
    var to: String
    var side: Side
    var kind: Kind
}

extension ScanArrow {
    /// From + to squares ("f3g5"): how arrows are compared and stored in
    /// `ScanAttemptDetail`. Side and kind follow from the squares.
    var line: String { from + to }
}
