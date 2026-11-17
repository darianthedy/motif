import Foundation

/// What the full scan's target step should find (format v2, optional in v1).
struct ScanTargets: Hashable, Codable, Sendable {
    /// Pieces that lose material.
    var red: [String] = []
    /// Pieces attacked as often as defended.
    var orange: [String] = []
    var kingZone: [String] = []
    var fork: [String] = []

    var allSquares: [String] { red + orange + kingZone + fork }
}
