import Foundation
import Observation

enum SolvePhase: Equatable { case solving, replying, solved, failed }
struct ResultLine { var steps: [Board.ReplayStep]; var played: Bool }
struct ResultMiss { var ply: Int; var tried: [String]; var wanted: String? }

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
    }
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
            if reply != nil || finished {
                phase = .replying
                replyTask = Task { [weak self, sleep] in
                    do {
                        if let reply {
                            try await sleep(REPLY_MS); try Task.checkCancellation()
                            guard let self else { return }
                            if let replied = Board.applyUci(self.fen, reply) { self.fen = replied; self.highlight = (moveFrom(reply), moveTo(reply)) }
                        }
                        try await sleep(150); try Task.checkCancellation()
                        guard let self else { return }
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
    var lines: [ResultLine] {
        guard done else { return [] }
        return puzzle.solutions.map { line in
            let solverMoves = line.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            let played = solverMoves.count == runner.accepted.count && zip(solverMoves, runner.accepted).allSatisfy { a, b in
                a == b || stripQueenPromotion(a) == b || stripQueenPromotion(b) == a
            }
            return ResultLine(steps: Board.replayLine(puzzle.fen, line), played: played)
        }
    }
    var misses: [ResultMiss] {
        guard done else { return [] }
        var plies: [Int] = [], groups: [Int: [String]] = [:]
        for miss in runner.misses {
            if groups[miss.ply] == nil { plies.append(miss.ply) }
            let san = askedFrom.indices.contains(miss.ply) ? Board.sanFor(askedFrom[miss.ply], miss.move) : nil
            groups[miss.ply, default: []].append(san ?? miss.move.text)
        }
        let played = lines.first { $0.played }
        return plies.map { ply in ResultMiss(ply: ply, tried: groups[ply] ?? [], wanted: played?.steps.indices.contains(ply * 2) == true ? played?.steps[ply * 2].san : nil) }
    }
    var verdict: String {
        if phase == .solved { return "Solved" }
        let total = lines.first { $0.played }?.steps.filter(\.bySolver).count ?? runner.accepted.count
        let numbers = misses.map { String($0.ply + 1) }
        var whereText = ""
        if total > 1, !numbers.isEmpty {
            whereText = numbers.count == 1 ? " on move \(numbers[0]) of \(total)" : " on moves \(numbers.dropLast().joined(separator: ", ")) and \(numbers.last!) of \(total)"
        }
        let noun = missing == nil ? "move" : "guess"
        return "Missed\(whereText) · \(mistakes) wrong \(noun)\(mistakes == 1 ? "" : missing == nil ? "s" : "es")\(hinted ? " · answer shown" : "")"
    }
}
