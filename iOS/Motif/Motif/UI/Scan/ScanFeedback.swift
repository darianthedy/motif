import Foundation

/// What a graded step shows under the board: a verdict with its symbol, a title and the one-line
/// reason (Mobile UX › Feedback). Pure, so every wording is tested without views.
struct ScanFeedback: Equatable, Sendable {
    enum Verdict: Equatable, Sendable {
        case pass, softMiss, fail

        /// A symbol as well as a colour, so the verdict never rests on colour alone.
        var systemImage: String {
            switch self {
            case .pass: "checkmark.circle.fill"
            case .softMiss: "exclamationmark.circle.fill"
            case .fail: "xmark.circle.fill"
            }
        }
    }

    var verdict: Verdict
    var title: String
    /// What was missed, or what the move cost; empty when the title says it all.
    var reason: String
    /// A second line when the puzzle's result needs one beyond the step's reason.
    var note: String?
    /// "7.4 / 10 s" ("… s limit" under a hard limit), or nil for a step without a target.
    var time: String?
    /// What was missed, one line per type (an icon, then the squares or moves), for the
    /// quick-scan, target and arrow steps; empty when nothing was, and for the move.
    var misses: [ScanMissGroup] = []

    /// The reason and the misses as VoiceOver reads them: "Their threat: Nb5, Bh8".
    var spokenReason: String {
        ([reason] + misses.map(\.spoken)).filter { !$0.isEmpty }.joined(separator: ". ")
    }

    /// The quick scan and flag call, graded together when Flag or No Flag ends the step. Short on
    /// purpose: the step's title and the rings on the board already say where things stand.
    static func quickScan(_ grade: ScanMarkGrade, flag: ScanFlagGrade, answer: ScanAnswer,
                          startFen: String, ms: Int) -> ScanFeedback {
        let time = timeText(ms, .quickScan)
        if flag == .fail {
            return ScanFeedback(verdict: .fail, title: "Missed the Flag", reason: "", time: time,
                                misses: missedSquares(grade.missed, answer, startFen))
        }
        if flag == .softMiss {
            return ScanFeedback(verdict: .softMiss, title: "No Flag Needed", reason: "", time: time)
        }
        if !grade.missed.isEmpty {
            let title = grade.missed.count == 1 ? "Missed a Square" : "Missed \(grade.missed.count) Squares"
            return ScanFeedback(verdict: .softMiss, title: title, reason: "", time: time,
                                misses: missedSquares(grade.missed, answer, startFen))
        }
        if ScanTiming.isOverTarget(ms, .quickScan) { return ScanFeedback(verdict: .softMiss, title: "Right, but Slow", reason: "", time: time) }
        return ScanFeedback(verdict: .pass, title: "Clean Scan", reason: "", time: time)
    }

    /// The target step. Misses are soft (Scoring); extra marks are never counted against.
    static func targets(_ grade: ScanMarkGrade, marked: [String: ScanTargetMark], answer: ScanAnswer,
                        startFen: String, ms: Int) -> ScanFeedback {
        let time = timeText(ms, .targets)
        if !grade.missed.isEmpty, let targets = answer.targets {
            let title = grade.missed.count == 1 ? "Missed a Target" : "Missed \(grade.missed.count) Targets"
            let misses = ScanMissGroup.grouped(grade.missed.map { square in
                let list: ScanMissCategory.Target = targets.red.contains(square) ? .red : targets.orange.contains(square) ? .orange
                    : targets.kingZone.contains(square) ? .kingZone : .fork
                return (.target(list), squareName(square, startFen))
            })
            return ScanFeedback(verdict: .softMiss, title: title, reason: "", time: time, misses: misses)
        }
        if ScanTiming.isOverTarget(ms, .targets) { return ScanFeedback(verdict: .softMiss, title: "Right, but Slow", reason: "", time: time) }
        return ScanFeedback(verdict: .pass, title: "All Targets Found", reason: "", time: time)
    }

    /// The arrow step. Misses are soft and only required arrows can be missed; extra arrows aren't graded.
    static func arrows(_ grade: ScanMarkGrade, answer: ScanAnswer, startFen: String, ms: Int) -> ScanFeedback {
        let time = timeText(ms, .arrows)
        let missed = grade.missed.compactMap { line in answer.arrows?.first { $0.line == line } }
        if !missed.isEmpty {
            let title = missed.count == 1 ? "Missed an Arrow" : "Missed \(missed.count) Arrows"
            let misses = ScanMissGroup.grouped(missed.map { arrow in
                (.arrow(arrow.kind, arrow.side), san(arrow, startFen))
            })
            return ScanFeedback(verdict: .softMiss, title: title, reason: "", time: time, misses: misses)
        }
        if ScanTiming.isOverTarget(ms, .arrows) { return ScanFeedback(verdict: .softMiss, title: "Right, but Slow", reason: "", time: time) }
        return ScanFeedback(verdict: .pass, title: "All Arrows Found", reason: "", time: time)
    }

    /// The move, and with it the puzzle's result: a missed Flag fails the puzzle whatever the move.
    static func move(_ move: Uci, grade: ScanMoveGrade, outcome: ScanOutcome, answer: ScanAnswer,
                     startFen: String, step: ScanTimedStep, ms: Int) -> ScanFeedback {
        let best = bestMove(answer).map { Board.sanFor(startFen, $0) ?? $0.text }
        let loss = grade.lossCp ?? 0
        let reason: String
        if loss == 0 { reason = "" }
        else if grade.passed { reason = loss > ScanGrader.marginCp ? "Keeps the mate." : "−\(pawns(loss)). Best: \(best ?? "?")." }
        else { reason = (loss >= ScanAnswer.lostMateCp ? "Throws away the mate." : "−\(pawns(loss)).") + (best.map { " Best: \($0)." } ?? "") }
        let note = outcome.detail.failReason == .missedFlag ? "Missed the Flag." : nil
        let verdict: Verdict = outcome.result == .failed ? .fail : outcome.detail.softMisses.isEmpty ? .pass : .softMiss
        let title: String
        switch (outcome.result, grade.passed) {
        case (.failed, false): title = "Mistake"
        case (.failed, true): title = "Good Move, Puzzle Failed"
        default:
            // Only over time: no square, target or arrow missed. Says so, so it doesn't read as a
            // miss in the summary's sense (a failed puzzle).
            let slowOnly = outcome.detail.softMisses.allSatisfy(\.isSlow)
            title = verdict == .pass ? "Passed" : slowOnly ? slowTitle(outcome.detail.softMisses) : "Passed with Misses"
        }
        return ScanFeedback(verdict: verdict, title: title, reason: reason, note: note, time: timeText(ms, step))
    }

    /// A pass where only time was missed. The card's time line is the move's, so a plain "Slow"
    /// means the move; an earlier step over its target is named (playtest 3: "Passed, Slow" sat
    /// over "2.8 / 5 s" when the quick scan was the slow one).
    private static func slowTitle(_ softMisses: [ScanSoftMiss]) -> String {
        if softMisses.contains(.moveSlow) { return "Passed, Slow" }
        let steps: [(ScanSoftMiss, String)] = [(.quickScanSlow, "Quick Scan"), (.targetsSlow, "Targets"), (.arrowsSlow, "Arrows")]
        let slow = steps.filter { softMisses.contains($0.0) }.map { $0.1 }
        switch slow.count {
        case 0: return "Passed"
        case 1: return "Passed, Slow \(slow[0])"
        default: return "Passed, Slow Scan"
        }
    }

    /// The quick scan's limit ran out before a call: the puzzle fails on any position.
    static func noCall(_ grade: ScanMarkGrade, answer: ScanAnswer, startFen: String, ms: Int) -> ScanFeedback {
        ScanFeedback(verdict: .fail, title: "Time's Up", reason: answer.flagged ? "Needed a Flag." : "Quiet.",
                     time: timeText(ms, .quickScan, limited: true))
    }

    /// The move step's limit ran out before a move was played: the puzzle fails (Scoring).
    static func noMove(outcome: ScanOutcome, answer: ScanAnswer, startFen: String, step: ScanTimedStep, ms: Int) -> ScanFeedback {
        let best = bestMove(answer).map { Board.sanFor(startFen, $0) ?? $0.text }
        let note = outcome.detail.failReason == .missedFlag ? "Missed the Flag." : nil
        return ScanFeedback(verdict: .fail, title: "Time's Up", reason: best.map { "Best: \($0)." } ?? "", note: note,
                            time: timeText(ms, step, limited: true))
    }

    /// The same feedback for a step played under a hard limit: the time line names the limit, and
    /// when it ran out the title says so and a pass becomes a soft miss (over the target).
    func limited(_ limitMs: Int?, timedOut: Bool) -> ScanFeedback {
        guard let limitMs else { return self }
        var copy = self
        if let time, let slash = time.range(of: " / ") { copy.time = String(time[..<slash.lowerBound]) + " / \(limitMs / 1000) s limit" }
        if timedOut {
            copy.title = "Time's Up"
            if verdict == .pass { copy.verdict = .softMiss }
        }
        return copy
    }

    /// The best line's first move when the maker scored it best, else the first move scored 0.
    static func bestMove(_ answer: ScanAnswer) -> Uci? {
        if let first = answer.bestLine?.first, answer.moves[first.text] == 0 { return first }
        return answer.moves.filter { $0.value == 0 }.keys.sorted().first.flatMap(Uci.parse)
    }

    /// The missed quick-scan squares by kind ("Ne4" attacked, "c6" undefended).
    private static func missedSquares(_ missed: [String], _ answer: ScanAnswer, _ startFen: String) -> [ScanMissGroup] {
        ScanMissGroup.grouped(missed.map { square in
            (.quickScan(answer.quickScan.first(where: { $0.square == square })?.kind), squareName(square, startFen))
        })
    }

    /// The arrow as the move it is ("Nb5", "Bxf7+"), for either side. One that isn't a legal move
    /// (a pinned piece's threat) is still written as one, from the piece and the squares.
    static func san(_ arrow: ScanArrow, _ fen: String) -> String {
        san(from: arrow.from, to: arrow.to, fen, check: arrow.kind == .check)
    }

    /// Any arrow in SAN, so the card and the arrow chips write moves one way (playtest 3).
    static func san(from: String, to: String, _ fen: String, check: Bool = false) -> String {
        if let san = ScanImport.arrowSans(fen, from: from, to: to).first { return san }
        let piece = Board.pieceAt(fen, from)
        let takes = Board.pieceAt(fen, to) != nil
        let name = piece.map { $0.type == .pawn ? (takes ? String(from.prefix(1)) : "") : $0.type.rawValue.uppercased() } ?? ""
        return name + (takes ? "x" : "") + to + (check ? "+" : "")
    }

    /// The piece and its square as in SAN ("Ne4", "e4" for a pawn), or the bare square when empty.
    private static func squareName(_ square: String, _ fen: String) -> String {
        guard let piece = Board.pieceAt(fen, square), piece.type != .pawn else { return square }
        return piece.type.rawValue.uppercased() + square
    }

    static func pawns(_ cp: Int) -> String { String(format: "%.1f", Double(cp) / 100) }

    static func seconds(_ ms: Int) -> String { String(format: "%.1f s", Double(ms) / 1000) }

    /// "7.4 / 10 s", or "10.0 / 10 s limit" under a hard limit.
    private static func timeText(_ ms: Int, _ step: ScanTimedStep, limited: Bool = false) -> String {
        "\(String(format: "%.1f", Double(ms) / 1000)) / \(ScanTiming.targetMs(step) / 1000) s" + (limited ? " limit" : "")
    }
}
