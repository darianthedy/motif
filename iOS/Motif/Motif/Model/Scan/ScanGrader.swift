import Foundation

/// Compares what the user did with the maker's answer. Pure: no state, no
/// engine, no clock, so every result can be tested from fixtures.
enum ScanGrader {
    /// A move passes within half a pawn of the best (plan §1.3).
    static let marginCp = 50

    /// Quick scan: the squares tapped against the answer's. Extras are
    /// recorded but not counted against (Scoring lists only misses).
    static func gradeQuickScan(tapped: Set<String>, answer: ScanAnswer) -> ScanMarkGrade {
        compare(expected: answer.quickScan.map(\.square), marked: tapped)
    }

    /// No Flag on a flagged position fails; Flag on a quiet one is a soft miss.
    static func gradeFlag(called: Bool, answer: ScanAnswer) -> ScanFlagGrade {
        switch (called, answer.flagged) {
        case (false, true): .fail
        case (true, false): .softMiss
        default: .pass
        }
    }

    /// Targets (v2): a piece counts when it has the right colour, an empty
    /// square when it has a dot (king zone and fork look the same). Nil when
    /// the puzzle has no targets, so the step is skipped.
    static func gradeTargets(red: Set<String>, orange: Set<String>, dots: Set<String>,
                             answer: ScanAnswer) -> ScanMarkGrade? {
        guard let targets = answer.targets else { return nil }
        let missed = targets.red.filter { !red.contains($0) }
            + targets.orange.filter { !orange.contains($0) }
            + (targets.kingZone + targets.fork).filter { !dots.contains($0) }
        let extra = red.union(orange).union(dots).subtracting(targets.allSquares)
        return ScanMarkGrade(missed: unique(missed), extra: extra.sorted())
    }

    /// Arrows (v2), as from + to squares ("f3g5"). Extra arrows aren't graded.
    /// Nil when the puzzle has no arrows, so the step is skipped.
    static func gradeArrows(drawn: Set<String>, answer: ScanAnswer) -> ScanMarkGrade? {
        guard let arrows = answer.arrows else { return nil }
        return compare(expected: arrows.map(\.line), marked: drawn)
    }

    /// Passes within `margin` of the best, or when it keeps a forced mate.
    static func gradeMove(_ move: Uci, answer: ScanAnswer, margin: Int = marginCp) -> ScanMoveGrade {
        guard let loss = answer.lossCp(move) else { return ScanMoveGrade(passed: false, lossCp: nil) }
        return ScanMoveGrade(passed: passes(lossCp: loss, answer: answer, margin: margin), lossCp: loss)
    }

    /// A forced mate is on when the maker scored some move as throwing it away
    /// (exactly `lostMateCp`); then every move that doesn't, keeps it.
    static func passes(lossCp: Int, answer: ScanAnswer, margin: Int = marginCp) -> Bool {
        if lossCp <= margin { return true }
        let mateOn = answer.moves.values.contains(ScanAnswer.lostMateCp)
        return mateOn && lossCp < ScanAnswer.lostMateCp
    }

    /// Folds the steps into pass or fail, the soft misses and the fail reason
    /// (Scoring). The first failing step gives the reason. A step the limit cut off counts as
    /// over its target.
    static func result(of steps: ScanSteps, flagCall: Bool, answer: ScanAnswer,
                       margin: Int = marginCp) -> ScanOutcome {
        var soft: [ScanSoftMiss] = []
        var reason: ScanFailReason?

        // A quick scan that ran out had no call: it fails whatever the position.
        if steps.quickScan?.timedOut == true {
            reason = .noCall
        } else {
            switch gradeFlag(called: flagCall, answer: answer) {
            case .fail: reason = .missedFlag
            case .softMiss: soft.append(.flaggedQuiet)
            case .pass: break
            }
        }
        if let step = steps.quickScan {
            if !step.missed.isEmpty { soft.append(.quickScanMissed) }
            if step.timedOut == true || ScanTiming.isOverTarget(step.ms, .quickScan) { soft.append(.quickScanSlow) }
        }
        if let step = steps.targets {
            if !step.missed.isEmpty { soft.append(.targetsMissed) }
            if step.timedOut == true || ScanTiming.isOverTarget(step.ms, .targets) { soft.append(.targetsSlow) }
        }
        if let step = steps.arrows {
            if !step.missed.isEmpty { soft.append(.arrowsMissed) }
            if step.timedOut == true || ScanTiming.isOverTarget(step.ms, .arrows) { soft.append(.arrowsSlow) }
        }
        // A move the limit cut off is over the target too, whatever the clock said.
        if let step = steps.move, step.played == nil || ScanTiming.isOverTarget(step.ms, .move(flagCall: flagCall)) {
            soft.append(.moveSlow)
        }
        if reason == nil {
            if let played = steps.move?.played {
                if !gradeMove(played, answer: answer, margin: margin).passed { reason = .badMove }
            } else {
                reason = .noMove
            }
        }
        let detail = ScanAttemptDetail(steps: steps, softMisses: soft, failReason: reason)
        return ScanOutcome(result: reason == nil ? .solved : .failed, detail: detail)
    }

    private static func compare(expected: [String], marked: Set<String>) -> ScanMarkGrade {
        ScanMarkGrade(missed: unique(expected.filter { !marked.contains($0) }),
                      extra: marked.subtracting(expected).sorted())
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0).inserted }
    }
}
