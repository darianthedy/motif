import Foundation

/// Per-step target times. Timing is record-only for now: every step is timed
/// and going over its target is a soft miss, but nothing is cut off. Hard
/// limits (14 days in, once a step's median is under its target) come in S09.
enum ScanTiming {
    static func targetMs(_ step: ScanTimedStep) -> Int {
        switch step {
        case .quickScan: 10_000
        case .quietMove: 5_000
        case .targets: 20_000
        case .arrows: 15_000
        case .flaggedMove: 10_000
        }
    }

    /// The hard limit for a step, nil while record-only.
    static func limitMs(_ step: ScanTimedStep) -> Int? { nil }

    static func isOverTarget(_ ms: Int, _ step: ScanTimedStep) -> Bool { ms > targetMs(step) }
}
