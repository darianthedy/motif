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
    var reason: String
    /// A second line when the puzzle's result needs one beyond the step's reason.
    var note: String?
    /// "7.4 s · target 10 s", or nil for a step without a target.
    var time: String?

    /// The quick scan and flag call, graded together when Flag or No Flag ends the step.
    static func quickScan(_ grade: ScanMarkGrade, flag: ScanFlagGrade, answer: ScanAnswer,
                          startFen: String, ms: Int) -> ScanFeedback {
        let slow = ScanTiming.isOverTarget(ms, .quickScan)
        let time = timeText(ms, .quickScan)
        if flag == .fail {
            let reason = grade.missed.isEmpty ? "This position needed a Flag." : "Needed a Flag: " + missedText(grade.missed, answer, startFen)
            return ScanFeedback(verdict: .fail, title: "Missed the Flag", reason: reason, time: time)
        }
        if flag == .softMiss {
            return ScanFeedback(verdict: .softMiss, title: "No Flag Needed", reason: "Nothing here needed a Flag: a quiet position.", time: time)
        }
        if !grade.missed.isEmpty {
            let title = grade.missed.count == 1 ? "Missed a Square" : "Missed \(grade.missed.count) Squares"
            return ScanFeedback(verdict: .softMiss, title: title, reason: missedText(grade.missed, answer, startFen), time: time)
        }
        let found = answer.quickScan.isEmpty ? "Nothing the last move changed needed a look." : "Found everything the last move changed."
        if slow { return ScanFeedback(verdict: .softMiss, title: "Right, but Slow", reason: found, time: time) }
        return ScanFeedback(verdict: .pass, title: "Clean Scan", reason: found, time: time)
    }

    /// The target step. Misses are soft (Scoring); extra marks are never counted against.
    static func targets(_ grade: ScanMarkGrade, marked: [String: ScanTargetMark], answer: ScanAnswer,
                        startFen: String, ms: Int) -> ScanFeedback {
        let time = timeText(ms, .targets)
        if let first = grade.missed.first, let targets = answer.targets {
            let title = grade.missed.count == 1 ? "Missed a Target" : "Missed \(grade.missed.count) Targets"
            let name = squareName(first, startFen)
            let reason: String
            if targets.red.contains(first) {
                reason = marked[first] == .orange ? "\(capitalized(name)) is red: it loses material." : "Missed \(name), which loses material."
            } else if targets.orange.contains(first) {
                reason = marked[first] == .red ? "\(capitalized(name)) is orange: attacked as often as defended, nothing lost yet."
                    : "Missed \(name), attacked as often as defended."
            } else if targets.kingZone.contains(first) {
                reason = "Missed \(first), a square by the king."
            } else {
                reason = "Missed \(first), a fork square."
            }
            return ScanFeedback(verdict: .softMiss, title: title, reason: reason + more(grade.missed), time: time)
        }
        let found = answer.targets?.allSquares.isEmpty ?? true ? "Nothing here needed a target." : "Found every target."
        if ScanTiming.isOverTarget(ms, .targets) { return ScanFeedback(verdict: .softMiss, title: "Right, but Slow", reason: found, time: time) }
        return ScanFeedback(verdict: .pass, title: "All Targets Found", reason: found, time: time)
    }

    /// The arrow step. Misses are soft; extra arrows aren't graded.
    static func arrows(_ grade: ScanMarkGrade, answer: ScanAnswer, startFen: String, ms: Int) -> ScanFeedback {
        let time = timeText(ms, .arrows)
        if let first = grade.missed.first, let arrow = answer.arrows?.first(where: { $0.line == first }) {
            let title = grade.missed.count == 1 ? "Missed an Arrow" : "Missed \(grade.missed.count) Arrows"
            let whose = arrow.side == .own ? "your" : "their"
            let kind: String
            switch arrow.kind {
            case .check: kind = "check"
            case .capture: kind = "capture"
            case .threat: kind = "threat"
            }
            let piece = Board.pieceAt(startFen, arrow.from).map { "the \($0.type.name.lowercased())" } ?? "the piece"
            let reason = "Missed \(whose) \(kind): \(piece) from \(arrow.from) to \(arrow.to)."
            return ScanFeedback(verdict: .softMiss, title: title, reason: reason + more(grade.missed), time: time)
        }
        let found = answer.arrows?.isEmpty ?? true ? "No check, capture or threat here needed an arrow."
            : "Found every check, capture and threat."
        if ScanTiming.isOverTarget(ms, .arrows) { return ScanFeedback(verdict: .softMiss, title: "Right, but Slow", reason: found, time: time) }
        return ScanFeedback(verdict: .pass, title: "All Arrows Found", reason: found, time: time)
    }

    /// The move, and with it the puzzle's result: a missed Flag fails the puzzle whatever the move.
    static func move(_ move: Uci, grade: ScanMoveGrade, outcome: ScanOutcome, answer: ScanAnswer,
                     startFen: String, flagCall: Bool, ms: Int) -> ScanFeedback {
        let san = Board.sanFor(startFen, move) ?? move.text
        let best = bestMove(answer).map { Board.sanFor(startFen, $0) ?? $0.text }
        let loss = grade.lossCp ?? 0
        let reason: String
        if grade.passed {
            if loss == 0 { reason = "\(san) is the best move." }
            else if loss > ScanGrader.marginCp { reason = "\(san) keeps the forced mate." }
            else { reason = "\(san) is within half a pawn of \(best ?? "the best move") (−\(pawns(loss)))." }
        } else {
            let lost = loss >= ScanAnswer.lostMateCp ? "\(san) throws away a forced mate." : "\(san) loses \(pawns(loss))."
            reason = lost + (best.map { " Best was \($0)." } ?? "")
        }
        let note = outcome.detail.failReason == .missedFlag ? "Failed: No Flag on a flagged position." : nil
        let verdict: Verdict = outcome.result == .failed ? .fail : outcome.detail.softMisses.isEmpty ? .pass : .softMiss
        let title: String
        switch (outcome.result, grade.passed) {
        case (.failed, false): title = "Mistake"
        case (.failed, true): title = "Good Move, Puzzle Failed"
        default: title = verdict == .pass ? "Passed" : "Passed with Misses"
        }
        return ScanFeedback(verdict: verdict, title: title, reason: reason, note: note,
                            time: timeText(ms, .move(flagCall: flagCall)))
    }

    /// The best line's first move when the maker scored it best, else the first move scored 0.
    static func bestMove(_ answer: ScanAnswer) -> Uci? {
        if let first = answer.bestLine?.first, answer.moves[first.text] == 0 { return first }
        return answer.moves.filter { $0.value == 0 }.keys.sorted().first.flatMap(Uci.parse)
    }

    /// "the knight on e4, now attacked", plus how many more.
    private static func missedText(_ missed: [String], _ answer: ScanAnswer, _ startFen: String) -> String {
        guard let first = missed.first else { return "" }
        let kind = answer.quickScan.first { $0.square == first }?.kind
        let piece = Board.pieceAt(startFen, first).map { "the \($0.type.name.lowercased()) on \(first)" } ?? first
        let why: String
        switch kind {
        case .attacked?: why = "now attacked"
        case .opened?: why = "on a line the move opened"
        case .undefended?: why = "no longer defended"
        case nil: why = "changed by the last move"
        }
        let more = missed.count > 1 ? " (and \(missed.count - 1) more)" : ""
        return "Missed \(piece), \(why)\(more)."
    }

    /// "the knight on e4", or the bare square when it's empty.
    private static func squareName(_ square: String, _ fen: String) -> String {
        Board.pieceAt(fen, square).map { "the \($0.type.name.lowercased()) on \(square)" } ?? square
    }

    private static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    /// " (and 2 more)" after the first miss.
    private static func more(_ missed: [String]) -> String {
        missed.count > 1 ? " (and \(missed.count - 1) more)" : ""
    }

    static func pawns(_ cp: Int) -> String { String(format: "%.1f", Double(cp) / 100) }

    static func seconds(_ ms: Int) -> String { String(format: "%.1f s", Double(ms) / 1000) }

    private static func timeText(_ ms: Int, _ step: ScanTimedStep) -> String {
        "\(seconds(ms)) · target \(ScanTiming.targetMs(step) / 1000) s"
    }
}
