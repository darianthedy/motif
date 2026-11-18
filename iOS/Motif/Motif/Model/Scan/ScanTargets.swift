import Foundation

/// What the full scan's target step should find (format v2, optional in v1).
struct ScanTargets: Hashable, Codable, Sendable {
    /// Pieces that lose material; from v3 also empty king-zone squares attacked more than defended.
    var red: [String] = []
    /// Pieces attacked as often as defended; from v3 also empty king-zone squares at 1–1, 2–2, …
    var orange: [String] = []
    /// Empty king-zone squares marked with a dot: only those that aren't red or orange.
    var kingZone: [String] = []
    var fork: [String] = []

    var allSquares: [String] { red + orange + kingZone + fork }
}
