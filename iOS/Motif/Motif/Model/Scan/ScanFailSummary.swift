import Foundation

/// One recent fail, as the Caïssa export lists it: the position, the last move, and what went wrong.
struct ScanFailSummary: Equatable, Sendable {
    var puzzleId: String
    var playedAt: Int64
    var fenBefore: String
    /// "3... Nf6 (g8f6)".
    var lastMove: String
    /// "Missed the flag", "Bxf7 lost 3.1", "No move in time", "No call in time".
    var reason: String
    /// What was missed, step by step: "quick scan c6 (undefended)", "arrows f3g5 (threat)".
    var missed: [String]

    init(_ attempt: ScanAttempt, _ puzzle: ScanPuzzle) {
        puzzleId = puzzle.id; playedAt = attempt.playedAt; fenBefore = puzzle.fenBefore
        let san = Board.sanFor(puzzle.fenBefore, puzzle.lastMove) ?? puzzle.lastMove.text
        lastMove = [moveNumber(puzzle.fenBefore, true), san].compactMap { $0 }.joined(separator: " ") + " (\(puzzle.lastMove.text))"
        reason = Self.describeReason(attempt, puzzle)
        missed = Self.describeMissed(attempt.detail.steps, puzzle.answer)
    }

    private static func describeReason(_ attempt: ScanAttempt, _ puzzle: ScanPuzzle) -> String {
        switch attempt.detail.failReason {
        case .missedFlag: return "No Flag on a flagged position"
        case .noCall: return "No call in time"
        case .noMove: return "No move in time"
        case .badMove, nil:
            guard let move = attempt.detail.steps.move, let played = move.played else { return "Failed" }
            let san = puzzle.startFen.flatMap { Board.sanFor($0, played) } ?? played.text
            guard let loss = move.lossCp else { return "\(san) failed" }
            return loss >= ScanAnswer.lostMateCp ? "\(san) let a mate go" : "\(san) lost " + pawns(loss)
        }
    }

    /// Centipawns as pawns with one decimal, in a fixed locale so the export reads the same anywhere.
    static func pawns(_ cp: Int) -> String { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double(cp) / 100) }

    private static func describeMissed(_ steps: ScanSteps, _ answer: ScanAnswer) -> [String] {
        var out: [String] = []
        if let step = steps.quickScan, !step.missed.isEmpty {
            let kinds = Dictionary(answer.quickScan.map { ($0.square, $0.kind.rawValue) }, uniquingKeysWith: { a, _ in a })
            out.append("quick scan " + step.missed.map { labelled($0, kinds[$0]) }.joined(separator: ", "))
        }
        // An attempt from before v6: its target misses, unlabelled now the answer has no targets.
        if let step = steps.targets, !step.missed.isEmpty {
            out.append("targets " + step.missed.joined(separator: ", "))
        }
        if let step = steps.arrows, !step.missed.isEmpty {
            let kinds = Dictionary((answer.arrows ?? []).map { ($0.line, $0.kind.rawValue) }, uniquingKeysWith: { a, _ in a })
            out.append("arrows " + step.missed.map { labelled($0, kinds[$0]) }.joined(separator: ", "))
        }
        return out
    }

    private static func labelled(_ item: String, _ label: String?) -> String { label.map { "\(item) (\($0))" } ?? item }
}
