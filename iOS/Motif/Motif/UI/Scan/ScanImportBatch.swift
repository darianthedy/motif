/// What an import adds to the pool: every accepted puzzle, and how many are new. A puzzle
/// already in the pool (same `contentKey`) is updated in place and keeps its progress.
struct ScanImportBatch: Equatable, Sendable {
    var puzzles: [ScanPuzzleContent] = []
    var added = 0
    var rejected = 0
    var updated: Int { puzzles.count - added }
    /// "2 added, 1 updated, 1 rejected." Parts that are zero are left out.
    var description: String {
        let parts = [(added, "added"), (updated, "updated"), (rejected, "rejected")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        guard added + updated > 0 else { return "Nothing to add." }
        return parts.joined(separator: ", ") + "."
    }
}
