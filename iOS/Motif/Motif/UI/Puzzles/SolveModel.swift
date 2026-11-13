import Foundation
import Observation

enum SolvePhase: Equatable { case solving, replying, solved, failed }
struct ResultLine { var steps: [Board.ReplayStep]; var played: Bool }
struct ResultMiss { var ply: Int; var tried: [String]; var wanted: String? }

/// How long a moved piece slides into place (`BoardView`).
let SLIDE_MS = 180

/// Positions and reply tasks belong to one attempt. The runner tracks answer
/// matching; this model owns the board and the visible timing around it.
@Observable @MainActor final class SolveModel {
    let puzzle: Puzzle
    private(set) var fen: String
    private(set) var phase = SolvePhase.solving
    private(set) var hint: Uci?
    private(set) var placementHint: Placement?
    private(set) var highlight: (from: String, to: String)?
    private(set) var shakeKey = 0
    @ObservationIgnored let runner: PuzzleRunner
    @ObservationIgnored let missing: MissingPieceRunner?
    @ObservationIgnored private var askedFrom: [String] = []
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private let sleep: @Sendable (Int) async throws -> Void
    @ObservationIgnored private var warmTask: Task<Void, Never>?
    /// Every solution replayed from the start position; depends on the puzzle alone.
    @ObservationIgnored private var replays: [[Board.ReplayStep]]?
    /// The card's lines, misses and verdict, worked out once when the attempt ends: its body
    /// reads them many times per render (and `ViewThatFits` renders it twice).
    @ObservationIgnored private var summary: Summary?
    var done: Bool { phase == .solved || phase == .failed }
    var mistakes: Int { missing?.mistakes ?? runner.mistakes }
    var hinted: Bool { missing?.hinted ?? runner.hinted }
    var result: AttemptResult { phase == .solved ? .solved : .failed }
    var marked: (from: String, to: String)? {
        if let hint { return (moveFrom(hint), moveTo(hint)) }
        if let answer = puzzle.addPiece, done || placementHint != nil { return (answer.square, answer.square) }
        return highlight
    }
    init(_ puzzle: Puzzle, sleep: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(for: .milliseconds($0)) }) {
        self.puzzle = puzzle; fen = puzzle.fen; runner = PuzzleRunner(puzzle)
        missing = puzzle.addPiece.map { MissingPieceRunner(puzzle, $0) }; self.sleep = sleep
        // The result card's lines (SAN and mate marks for every solution) are ready before
        // the puzzle ends, off the main actor, so the card appears without a hitch.
        let start = puzzle.fen, solutions = puzzle.solutions
        warmTask = Task.detached(priority: .utility) { [weak self] in
            let steps = solutions.map { Board.replayLine(start, $0) }
            await self?.warmed(steps)
        }
    }
    private func warmed(_ steps: [[Board.ReplayStep]]) { if replays == nil { replays = steps } }
    func cancel() { replyTask?.cancel(); replyTask = nil }
    func submit(_ move: Uci) {
        guard phase == .solving, missing == nil, Board.isLegal(fen, move) else { return }
        if askedFrom.count == runner.accepted.count { askedFrom.append(fen) }
        switch runner.submit(move) {
        case .wrong:
            shakeKey += 1
            if runner.shouldRevealHint { hint = runner.revealHint() }
        case .correct(let reply, let finished):
            guard let next = Board.applyUci(fen, move) else { return }
            fen = next; highlight = (moveFrom(move), moveTo(move)); hint = nil
            // A last move with nothing to answer ends the attempt at once, as on the web.
            if reply == nil && finished { phase = runner.result == .solved ? .solved : .failed }
            if let reply {
                phase = .replying
                replyTask = Task { [weak self, sleep] in
                    do {
                        try await sleep(REPLY_MS); try Task.checkCancellation()
                        guard let self else { return }
                        if let replied = Board.applyUci(self.fen, reply) { self.fen = replied; self.highlight = (moveFrom(reply), moveTo(reply)) }
                        // The card waits for the reply's slide (BoardView, 0.18 s); the next move
                        // doesn't, so the board is live as soon as the reply lands.
                        if finished { try await sleep(SLIDE_MS); try Task.checkCancellation() }
                        self.phase = finished ? (self.runner.result == .solved ? .solved : .failed) : .solving
                    } catch { /* Leaving the attempt cancels its reply. */ }
                }
            }
        }
    }
    func submit(_ placement: Placement) {
        guard phase == .solving, let missing else { return }
        switch missing.submit(placement.square, placement.type) {
        case .wrong:
            shakeKey += 1
            if missing.shouldRevealHint { placementHint = missing.revealHint() }
        case .correct:
            fen = Board.withPiece(puzzle.fen, missing.answer) ?? puzzle.fen
            phase = missing.result == .solved ? .solved : .failed
        }
    }
    var lines: [ResultLine] { summarized()?.lines ?? [] }
    var misses: [ResultMiss] { summarized()?.misses ?? [] }
    var verdict: String { summarized()?.verdict ?? "" }
    private struct Summary { var lines: [ResultLine]; var misses: [ResultMiss]; var verdict: String }
    /// Nil until the attempt ends. Reading `done` keeps observers on `phase`.
    private func summarized() -> Summary? {
        guard done else { return nil }
        if let summary { return summary }
        let replays = replays ?? puzzle.solutions.map { Board.replayLine(puzzle.fen, $0) }
        self.replays = replays; warmTask?.cancel()
        let lines = zip(puzzle.solutions, replays).map { line, steps in
            let solverMoves = line.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            let played = solverMoves.count == runner.accepted.count && zip(solverMoves, runner.accepted).allSatisfy { a, b in
                a == b || stripQueenPromotion(a) == b || stripQueenPromotion(b) == a
            }
            return ResultLine(steps: steps, played: played)
        }
        let played = lines.first { $0.played }
        var plies: [Int] = [], groups: [Int: [String]] = [:]
        for miss in runner.misses {
            if groups[miss.ply] == nil { plies.append(miss.ply) }
            let san = askedFrom.indices.contains(miss.ply) ? Board.sanFor(askedFrom[miss.ply], miss.move) : nil
            groups[miss.ply, default: []].append(san ?? miss.move.text)
        }
        let misses = plies.map { ply in ResultMiss(ply: ply, tried: groups[ply] ?? [], wanted: played?.steps.indices.contains(ply * 2) == true ? played?.steps[ply * 2].san : nil) }
        let summary = Summary(lines: lines, misses: misses, verdict: verdictText(played, misses))
        self.summary = summary
        return summary
    }
    private func verdictText(_ played: ResultLine?, _ misses: [ResultMiss]) -> String {
        if phase == .solved { return "Solved" }
        let total = played?.steps.filter(\.bySolver).count ?? runner.accepted.count
        let numbers = misses.map { String($0.ply + 1) }
        var whereText = ""
        if total > 1, !numbers.isEmpty {
            whereText = numbers.count == 1 ? " on move \(numbers[0]) of \(total)" : " on moves \(numbers.dropLast().joined(separator: ", ")) and \(numbers.last!) of \(total)"
        }
        let noun = missing == nil ? "move" : "guess"
        return "Missed\(whereText) · \(mistakes) wrong \(noun)\(mistakes == 1 ? "" : missing == nil ? "s" : "es")\(hinted ? " · answer shown" : "")"
    }
}
