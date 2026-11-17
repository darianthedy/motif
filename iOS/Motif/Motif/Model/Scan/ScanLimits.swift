import Foundation

/// The hard limits in force for one puzzle, from `ScanTiming.limits`. Empty while record-only.
struct ScanLimits: Equatable, Sendable {
    var on: Set<ScanTimedStep> = []

    /// The step's hard limit (its target time), or nil while it's record-only.
    func limitMs(_ step: ScanTimedStep) -> Int? { on.contains(step) ? ScanTiming.targetMs(step) : nil }

    var isEmpty: Bool { on.isEmpty }
}
