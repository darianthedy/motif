import Foundation

/// Compares what the user did with the maker's answer. Pure: no state, no
/// engine, no clock, so every result can be tested from fixtures.
enum ScanGrader {
    /// A move passes within half a pawn of the best (plan §1.3).
    static let marginCp = 50

    /// From here the best move is clearly winning, and a move is graded by the win chance it
    /// loses instead of `marginCp` (Scoring › Winning positions): the +3 trigger Caïssa uses.
    static let clearlyWinningCp = 300
    /// The most win chance a move may lose and still pass, in percentage points: under 10 is
    /// "fine" in `caissa/tools/engine.py check` (10 is its inaccuracy line).
    static let maxWinPctLost = 10.0

    /// Win chance from the mover's side, 0...100: Lichess's curve, as `engine.py win_pct`.
    static func winPct(_ cp: Int) -> Double {
        50 + 50 * (2 / (1 + exp(-0.00368208 * Double(cp))) - 1)
    }

    /// The win chance a move loses, in points, or nil when the answer has no `bestCp`.
    static func winPctLost(lossCp: Int, answer: ScanAnswer) -> Double? {
        guard let best = answer.bestCp else { return nil }
        return winPct(best) - winPct(best - lossCp)
    }

    /// Quick scan: the squares tapped against the answer's. Extras are
    /// recorded but not counted against (Scoring lists only misses).
    static func gradeQuickScan(tapped: Set<String>, answer: ScanAnswer) -> ScanMarkGrade {
        compare(expected: answer.quickScan.map(\.square), marked: tapped)
    }

    /// Quiet on a tactical position fails; Tactic on a quiet one is a soft miss.
    static func gradeFlag(called: Bool, answer: ScanAnswer) -> ScanFlagGrade {
        switch (called, answer.flagged) {
        case (false, true): .fail
        case (true, false): .softMiss
        default: .pass
        }
    }

    /// Target marks made during the arrows (v6) are a thinking aid: never passed here, never graded.
    /// Arrows (v2), as from + to squares ("f3g5"). Every required arrow must be
    /// drawn; an optional one (v4) counts when drawn and isn't missed when left
    /// out. An arrow not in the list is extra. Nil when the puzzle has no
    /// arrows, so the step is skipped.
    static func gradeArrows(drawn: Set<String>, answer: ScanAnswer) -> ScanMarkGrade? {
        guard let arrows = answer.arrows else { return nil }
        let required = arrows.filter { !$0.optional }.map(\.line)
        return ScanMarkGrade(missed: unique(required.filter { !drawn.contains($0) }),
                             extra: drawn.subtracting(arrows.map(\.line)).sorted())
    }

    /// The first move. One that starts any of the puzzle's lines always passes (Scoring › Line
    /// moves); otherwise the maker's score decides (`passes`).
    static func gradeMove(_ move: Uci, answer: ScanAnswer, margin: Int = marginCp) -> ScanMoveGrade {
        let loss = answer.lossCp(move)
        if let solutions = answer.solutions, findEdge(buildTrie(solutions), move) != nil {
            return ScanMoveGrade(passed: true, lossCp: loss, onLine: true)
        }
        guard let loss else { return ScanMoveGrade(passed: false, lossCp: nil) }
        return ScanMoveGrade(passed: passes(lossCp: loss, answer: answer, margin: margin), lossCp: loss)
    }

    /// Within `margin` of the best; when the best is clearly winning (v7 `bestCp`), losing under
    /// `maxWinPctLost` win chance instead. A forced mate is on when the maker scored some move as
    /// throwing it away (exactly `lostMateCp`); then every move that doesn't, keeps it.
    static func passes(lossCp: Int, answer: ScanAnswer, margin: Int = marginCp) -> Bool {
        if lossCp <= margin { return true }
        if let best = answer.bestCp, best >= clearlyWinningCp,
           let lost = winPctLost(lossCp: lossCp, answer: answer), lost < maxWinPctLost { return true }
        let mateOn = answer.moves.values.contains(ScanAnswer.lostMateCp)
        return mateOn && lossCp < ScanAnswer.lostMateCp
    }

    /// The solver's later move in the line (v7): an exact match against the lines that still fit
    /// the moves so far, as normal puzzles match (`findEdge`). Nil when it's off every line.
    static func gradeLineMove(_ move: Uci, at node: TrieNode) -> TrieEdge? { findEdge(node, move) }

    /// The line to show: the first of the puzzle's lines that the moves on it so far (both
    /// sides, from the first move) fit, else the first line. Empty for a one-move puzzle.
    static func shownLine(_ answer: ScanAnswer, fitting played: [Uci]) -> [Uci] {
        let lines = answer.solutions ?? []
        func same(_ a: Uci, _ b: Uci) -> Bool { a == b || stripQueenPromotion(a) == b || stripQueenPromotion(b) == a }
        return lines.first { $0.count >= played.count && zip($0, played).allSatisfy(same) } ?? lines.first ?? []
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
        if let step = steps.arrows {
            if !step.missed.isEmpty { soft.append(.arrowsMissed) }
            if step.timedOut == true || ScanTiming.isOverTarget(step.ms, .arrows) { soft.append(.arrowsSlow) }
        }
        // A move the limit cut off is over the target too, whatever the clock said.
        if let step = steps.move, step.played == nil || ScanTiming.isOverTarget(step.ms, .move(flagCall: flagCall, steps: steps)) {
            soft.append(.moveSlow)
        }
        if reason == nil {
            if let played = steps.move?.played {
                if !gradeMove(played, answer: answer, margin: margin).passed { reason = .badMove }
                else if steps.line?.offLine == true { reason = .offLine }
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
