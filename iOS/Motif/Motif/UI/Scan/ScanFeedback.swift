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
    /// quick-scan and arrow steps; empty when nothing was, and for the move.
    var misses: [ScanMissGroup] = []

    /// The reason and the misses as VoiceOver reads them: "Their threat: Nb5, Bh8".
    var spokenReason: String {
        ([reason] + misses.map(\.spoken)).filter { !$0.isEmpty }.joined(separator: ". ")
    }

    /// The quick scan and flag call, graded together when Tactic or Quiet ends the step. Short on
    /// purpose: the step's title and the rings on the board already say where things stand.
    static func quickScan(_ grade: ScanMarkGrade, flag: ScanFlagGrade, answer: ScanAnswer,
                          startFen: String, ms: Int) -> ScanFeedback {
        let time = timeText(ms, .quickScan)
        if flag == .fail {
            return ScanFeedback(verdict: .fail, title: "Missed the Tactic", reason: "", time: time,
                                misses: missedSquares(grade.missed, answer, startFen))
        }
        if flag == .softMiss {
            return ScanFeedback(verdict: .softMiss, title: "It Was Quiet", reason: "", time: time)
        }
        if !grade.missed.isEmpty {
            // The quick scan flags pieces, not empty squares (playtest 4).
            let title = grade.missed.count == 1 ? "Missed a Piece" : "Missed \(grade.missed.count) Pieces"
            return ScanFeedback(verdict: .softMiss, title: title, reason: "", time: time,
                                misses: missedSquares(grade.missed, answer, startFen))
        }
        if ScanTiming.isOverTarget(ms, .quickScan) { return ScanFeedback(verdict: .softMiss, title: slowStepTitle, reason: "", time: time) }
        return ScanFeedback(verdict: .pass, title: "Clean Scan", reason: "", time: time)
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
        if ScanTiming.isOverTarget(ms, .arrows) { return ScanFeedback(verdict: .softMiss, title: slowStepTitle, reason: "", time: time) }
        return ScanFeedback(verdict: .pass, title: "All Arrows Found", reason: "", time: time)
    }

    /// The move, and with it the puzzle's result: a missed Tactic fails the puzzle whatever the move.
    /// On a puzzle with a line (v7), `line` is the one that fits what was played: a first move on
    /// it says nothing of its score, one off it that still passes ends the puzzle ("Also works"),
    /// and a later move off it fails with the line shown.
    static func move(_ move: Uci, grade: ScanMoveGrade, outcome: ScanOutcome, answer: ScanAnswer,
                     startFen: String, step: ScanTimedStep, ms: Int, line: [Uci]? = nil) -> ScanFeedback {
        let best = bestMove(answer).map { Board.sanFor(startFen, $0) ?? $0.text }
        let loss = grade.lossCp ?? 0
        let offLine = outcome.detail.steps.line?.offLine == true
        let lineText = lineSan(line ?? ScanGrader.shownLine(answer, fitting: []), startFen)
        var reason: String
        if offLine { reason = "The line was \(lineText)." }
        else if loss == 0 || grade.onLine { reason = "" }
        else if grade.passed {
            reason = loss > ScanGrader.marginCp && answer.moves.values.contains(ScanAnswer.lostMateCp)
                ? "Keeps the mate." : "−\(pawns(loss)). Best: \(best ?? "?")."
        }
        else { reason = (loss >= ScanAnswer.lostMateCp ? "Throws away the mate." : "−\(pawns(loss)).") + (best.map { " Best: \($0)." } ?? "") }
        if grade.passed, !grade.onLine, answer.hasLine, !lineText.isEmpty {
            reason = "Also works. The puzzle's line was \(lineText)."
        }
        let note = outcome.detail.failReason == .missedFlag ? "Missed the Tactic." : nil
        let verdict: Verdict = outcome.result == .failed ? .fail : outcome.detail.softMisses.isEmpty ? .pass : .softMiss
        let title: String
        switch (outcome.result, grade.passed) {
        case _ where offLine: title = "Off the Line"
        case (.failed, false): title = "Mistake"
        case (.failed, true): title = "Good Move, Puzzle Failed"
        default:
            // Only over time: no square or arrow missed. Says so, so it doesn't read as a
            // miss in the summary's sense (a failed puzzle).
            let misses = outcome.detail.softMisses
            title = verdict == .pass ? "Passed" : misses.allSatisfy(\.isSlow) ? slowTitle(misses) : "Passed with Misses"
        }
        return ScanFeedback(verdict: verdict, title: title, reason: reason, note: note, time: timeText(ms, step))
    }

    /// A step right but over its target: "Right · slow", the same pattern as the result's.
    static let slowStepTitle = "Right · slow"

    /// One pattern for a pass that was only slow, naming every slow step in the order played
    /// ("Passed · slow: Quick Scan, Move"), so the label never reads against the move's time
    /// (playtest 3) and never comes in three wordings (playtest 4).
    private static func slowTitle(_ misses: [ScanSoftMiss]) -> String {
        let steps: [String] = [(ScanSoftMiss.quickScanSlow, "Quick Scan"), (.arrowsSlow, "Arrows"), (.moveSlow, "Move")]
            .filter { misses.contains($0.0) }.map(\.1)
        return steps.isEmpty ? "Passed" : "Passed · slow: " + steps.joined(separator: ", ")
    }

    /// The quick scan's limit ran out before a call: the puzzle fails on any position.
    static func noCall(_ grade: ScanMarkGrade, answer: ScanAnswer, startFen: String, ms: Int) -> ScanFeedback {
        ScanFeedback(verdict: .fail, title: "Time's Up", reason: answer.flagged ? "Needed Tactic." : "Quiet.",
                     time: timeText(ms, .quickScan, limited: true))
    }

    /// The move step's limit ran out before a move was played: the puzzle fails (Scoring).
    static func noMove(outcome: ScanOutcome, answer: ScanAnswer, startFen: String, step: ScanTimedStep, ms: Int) -> ScanFeedback {
        let best = bestMove(answer).map { Board.sanFor(startFen, $0) ?? $0.text }
        let note = outcome.detail.failReason == .missedFlag ? "Missed the Tactic." : nil
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
        if let san = ScanImport.arrowSans(fen, from: arrow.from, to: arrow.to).first { return san }
        let piece = Board.pieceAt(fen, arrow.from)
        let takes = Board.pieceAt(fen, arrow.to) != nil
        let name = piece.map { $0.type == .pawn ? (takes ? String(arrow.from.prefix(1)) : "") : $0.type.rawValue.uppercased() } ?? ""
        return name + (takes ? "x" : "") + arrow.to + (arrow.kind == .check ? "+" : "")
    }

    /// The piece and its square as in SAN ("Ne4", "e4" for a pawn), or the bare square when empty.
    private static func squareName(_ square: String, _ fen: String) -> String {
        guard let piece = Board.pieceAt(fen, square), piece.type != .pawn else { return square }
        return piece.type.rawValue.uppercased() + square
    }

    /// A line in SAN with move numbers, from the position after the last move: "1. Qa4 Kb8 2. Qxa7#".
    static func lineSan(_ line: [Uci], _ startFen: String) -> String {
        var parts: [String] = [], position = startFen
        for (ply, step) in Board.replayLine(startFen, line).enumerated() {
            if let number = moveNumber(position, ply == 0) { parts.append(number) }
            parts.append(step.san)
            position = step.fen
        }
        return parts.joined(separator: " ")
    }

    static func pawns(_ cp: Int) -> String { String(format: "%.1f", Double(cp) / 100) }

    static func seconds(_ ms: Int) -> String { String(format: "%.1f s", Double(ms) / 1000) }

    /// "7.4 / 10 s", or "10.0 / 10 s limit" under a hard limit.
    private static func timeText(_ ms: Int, _ step: ScanTimedStep, limited: Bool = false) -> String {
        "\(String(format: "%.1f", Double(ms) / 1000)) / \(ScanTiming.targetMs(step) / 1000) s" + (limited ? " limit" : "")
    }
}
