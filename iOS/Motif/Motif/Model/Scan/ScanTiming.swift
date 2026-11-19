import Foundation

/// Per-step target times, and when they become hard limits (Scan plan §5, Scoring › Timing).
/// Every step is timed and going over its target is a soft miss. For the first 14 days after the
/// first scan attempt that's all (record-only). After that, a step's hard limit, equal to its
/// target, switches on once its median over the last 50 attempts is under the target, and stays
/// on. Worked out from the attempts alone, so every device agrees and nothing extra is stored.
enum ScanTiming {
    /// Record-only for this long after the first scan attempt.
    static let recordOnlyMs: Int64 = 14 * 24 * 60 * 60 * 1000
    /// How many of a step's most recent times its median is taken over.
    static let medianWindow = 50

    static func targetMs(_ step: ScanTimedStep) -> Int {
        switch step {
        case .quickScan: 10_000
        case .quietMove: 5_000
        case .arrows: 30_000
        case .flaggedMove: 10_000
        }
    }

    static func isOverTarget(_ ms: Int, _ step: ScanTimedStep) -> Bool { ms > targetMs(step) }

    /// The limits in force at `now` (epoch ms). `enabled` is the Time Limits switch: off, every
    /// step stays record-only, though whether a limit has been earned is still worked out.
    static func limits(_ attempts: [ScanAttempt], now: Int64, enabled: Bool = true) -> ScanLimits {
        guard enabled else { return ScanLimits() }
        return ScanLimits(on: earned(attempts, now: now))
    }

    /// The steps whose limit has switched on by `now`. A step's median only changes when an
    /// attempt is played, so it is checked when the record-only time ends, before each attempt
    /// played after that, and at `now`; once under the target at any of those, it stays on.
    static func earned(_ attempts: [ScanAttempt], now: Int64) -> Set<ScanTimedStep> {
        let graded = attempts.filter { $0.result != .skipped }.sorted { $0.playedAt < $1.playedAt }
        guard let first = graded.first?.playedAt else { return [] }
        let switchAt = first + recordOnlyMs
        guard now >= switchAt else { return [] }
        var on: Set<ScanTimedStep> = []
        var times: [ScanTimedStep: [Int]] = [:]
        func check() {
            for step in ScanTimedStep.allCases where !on.contains(step) {
                if let median = median(times[step] ?? []), median < Double(targetMs(step)) { on.insert(step) }
            }
        }
        for attempt in graded {
            if attempt.playedAt >= switchAt { check() }
            for (step, ms) in timed(attempt) {
                times[step, default: []].append(ms)
                if times[step]!.count > medianWindow { times[step]!.removeFirst() }
            }
        }
        check()
        return on
    }

    /// The median of a list of times; nil for none.
    static func median(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(), mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? Double(sorted[mid - 1] + sorted[mid]) / 2 : Double(sorted[mid])
    }

    /// Each timed step an attempt played, with its time.
    private static func timed(_ attempt: ScanAttempt) -> [(ScanTimedStep, Int)] {
        let steps = attempt.detail.steps
        var out: [(ScanTimedStep, Int)] = []
        if let step = steps.quickScan { out.append((.quickScan, step.ms)) }
        if let step = steps.arrows { out.append((.arrows, step.ms)) }
        if let step = steps.move, let flagCall = attempt.flagCall { out.append((.move(flagCall: flagCall, steps: steps), step.ms)) }
        return out
    }
}
