import Foundation

/// The Scan tab's Stats (Scan plan §8), worked out on the device from the attempts and the
/// pool alone, so there is nothing to store or keep in step. Skips count for nothing; every
/// other attempt is "played".
struct ScanStats: Equatable, Sendable {
    /// Graded attempts: solved plus failed.
    var played = 0
    var solved = 0
    /// The median over every quick scan played; a scan cut off by its limit counts at the limit.
    var quickScanMedianMs: Double?
    /// Played attempts whose call matched the maker's. A quick scan that ran out had no call, so
    /// it counts as wrong: accuracy is calls right over all played.
    var flagRight = 0
    /// Every category that came up in a step played, most missed first.
    var misses: [ScanMissTally] = []
    /// Weeks with play, oldest first, at most `weekCount` of them.
    var weeks: [ScanWeek] = []
    /// The share of Flag puzzles in the pool, so drift in the maker's Flag rule shows (§11.1).
    var poolSize = 0
    var flagPuzzles = 0
    /// The most recent fails, newest first, at most `recentFailCount`.
    var recentFails: [ScanFailSummary] = []

    static let weekCount = 12
    static let recentFailCount = 10

    var flagAccuracy: Double? { played == 0 ? nil : Double(flagRight) / Double(played) }
    var flagShare: Double? { poolSize == 0 ? nil : Double(flagPuzzles) / Double(poolSize) }
    /// The category missed most often; nil until something has been missed.
    var mostMissed: ScanMissTally? { misses.first { $0.missed > 0 } }

    init() {}

    /// `calendar` sets where a week starts; tests pass a fixed one.
    init(_ library: Library, calendar: Calendar = .current) {
        let puzzles = Dictionary(library.scanPuzzles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        poolSize = library.scanPuzzles.count
        flagPuzzles = library.scanPuzzles.filter(\.answer.flagged).count
        // Attempts cascade with their puzzle, so one without it is only a moment out of step.
        let graded = library.scanAttempts
            .filter { $0.result != .skipped && puzzles[$0.puzzleId] != nil }
            .sorted { $0.playedAt == $1.playedAt ? $0.id < $1.id : $0.playedAt < $1.playedAt }
        played = graded.count
        solved = graded.filter { $0.result == .solved }.count
        flagRight = graded.filter { Self.calledRight($0, puzzles[$0.puzzleId]!) }.count
        quickScanMedianMs = ScanTiming.median(graded.compactMap(\.detail.steps.quickScan?.ms))

        var tallies: [ScanMissCategory: ScanMissTally] = [:]
        for attempt in graded { Self.tally(attempt.detail.steps, puzzles[attempt.puzzleId]!.answer, into: &tallies) }
        let order = Dictionary(uniqueKeysWithValues: ScanMissCategory.allCases.enumerated().map { ($1, $0) })
        misses = tallies.values.filter { $0.expected > 0 }.sorted {
            if $0.missed != $1.missed { return $0.missed > $1.missed }
            if $0.missRate != $1.missRate { return $0.missRate > $1.missRate }
            return order[$0.category]! < order[$1.category]!
        }

        let byWeek = Dictionary(grouping: graded) { attempt in
            let date = Date(timeIntervalSince1970: TimeInterval(attempt.playedAt) / 1000)
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        }
        weeks = byWeek.keys.sorted().suffix(Self.weekCount).map { start in
            let attempts = byWeek[start]!
            return ScanWeek(start: start, played: attempts.count, solved: attempts.filter { $0.result == .solved }.count,
                            flagRight: attempts.filter { Self.calledRight($0, puzzles[$0.puzzleId]!) }.count,
                            quickScanMedianMs: ScanTiming.median(attempts.compactMap(\.detail.steps.quickScan?.ms)))
        }

        recentFails = graded.filter { $0.result == .failed }.suffix(Self.recentFailCount).reversed()
            .map { ScanFailSummary($0, puzzles[$0.puzzleId]!) }
    }

    static func calledRight(_ attempt: ScanAttempt, _ puzzle: ScanPuzzle) -> Bool {
        attempt.flagCall.map { $0 == puzzle.answer.flagged } ?? false
    }

    /// Counts what each step played had to find, and what it missed, by the answer's labels.
    /// A missed square the answer no longer has (the puzzle was re-sent since) isn't counted. An
    /// older attempt's target step isn't counted: targets aren't graded since v6.
    private static func tally(_ steps: ScanSteps, _ answer: ScanAnswer, into tallies: inout [ScanMissCategory: ScanMissTally]) {
        func add(_ category: ScanMissCategory, expected: Int = 0, missed: Int = 0) {
            tallies[category, default: ScanMissTally(category: category, expected: 0, missed: 0)].expected += expected
            tallies[category]!.missed += missed
        }
        if let step = steps.quickScan {
            for square in answer.quickScan { add(.quickScan(square.kind), expected: 1) }
            let kinds = Dictionary(answer.quickScan.map { ($0.square, $0.kind) }, uniquingKeysWith: { a, _ in a })
            for square in step.missed { if let kind = kinds[square] { add(.quickScan(kind), missed: 1) } }
        }
        if let step = steps.arrows, let arrows = answer.arrows {
            for arrow in arrows { add(.arrow(arrow.kind), expected: 1) }
            let kinds = Dictionary(arrows.map { ($0.line, $0.kind) }, uniquingKeysWith: { a, _ in a })
            for line in step.missed { if let kind = kinds[line] { add(.arrow(kind), missed: 1) } }
        }
    }
}
