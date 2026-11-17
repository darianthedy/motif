import Foundation

/// How often one category came up in a step that was played, and how often it was missed.
struct ScanMissTally: Equatable, Sendable {
    var category: ScanMissCategory
    /// Squares or arrows of this category in the answers of steps played.
    var expected: Int
    var missed: Int

    var missRate: Double { expected == 0 ? 0 : Double(missed) / Double(expected) }
}
