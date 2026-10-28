import Foundation
import Synchronization

/// The only way the app reaches a chess engine: UCI commands in, UCI lines out.
/// `StockfishEngine` adapts ChessKitEngine; `FakeEngine` replays scripted lines for
/// tests and the UI-test launch route.
protocol UCIEngine: AnyObject, Sendable {
    /// Queues one UCI command. Commands reach the engine in the order they're sent.
    func send(_ command: String)
    /// A new subscription to the engine's output, one line per element, starting now.
    /// Every subscriber sees every line.
    var lines: AsyncStream<String> { get }
}

/// Fans engine output out to every current subscriber.
final class LineBroadcast: Sendable {
    private let subscribers = Mutex<[UUID: AsyncStream<String>.Continuation]>([:])

    func subscribe() -> AsyncStream<String> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        continuation.onTermination = { [weak self] _ in self?.subscribers.withLock { $0[id] = nil } }
        subscribers.withLock { $0[id] = continuation }
        return stream
    }

    func yield(_ line: String) {
        for continuation in subscribers.withLock({ Array($0.values) }) { continuation.yield(line) }
    }
}

/// An engine that never searches. It records what it's sent, answers a command with
/// whatever `replies` scripts for it, and (like Stockfish) ends a running search with
/// a `bestmove` when it's told to `stop`, unless `answersStop` is off so a test can
/// hold that `bestmove` back and emit it itself.
final class FakeEngine: UCIEngine {
    private struct State {
        var sent: [String] = []
        var searching = false
    }

    private let output = LineBroadcast()
    private let state = Mutex(State())
    private let answersStop: Bool
    private let replies: @Sendable (String) -> [String]

    init(answersStop: Bool = true, replies: @escaping @Sendable (String) -> [String] = { _ in [] }) {
        self.answersStop = answersStop
        self.replies = replies
    }

    var lines: AsyncStream<String> { output.subscribe() }

    /// Every command received so far, oldest first.
    var sent: [String] { state.withLock { $0.sent } }

    func send(_ command: String) {
        let answer = state.withLock { state in
            state.sent.append(command)
            if command.hasPrefix("go") { state.searching = true }
            guard command == "stop", state.searching, answersStop else { return false }
            state.searching = false
            return true
        }
        for line in replies(command) { emit(line) }
        if answer { emit("bestmove 0000") }
    }

    /// Delivers one output line to every subscriber.
    func emit(_ line: String) {
        if line.hasPrefix("bestmove") { state.withLock { $0.searching = false } }
        output.yield(line)
    }
}

extension FakeEngine {
    /// The `game-eval` route's engine: every `go` climbs from depth 1 to `Analyzer.targetDepth`
    /// and ends with a `bestmove`. The score is +0.6 for White at the start and a tenth of a
    /// pawn more for every ply after it, so each position's value is its own. With MultiPV
    /// set, line N plays the Nth legal move (squares a1 to h8) and scores a tenth less per rank.
    static func climb() -> FakeEngine {
        let position = LastPosition()
        return FakeEngine { command in
            if command.hasPrefix("position fen ") { position.fen.withLock { $0 = String(command.dropFirst("position fen ".count)) } }
            if command.hasPrefix("setoption name MultiPV value "), let count = Int(command.split(separator: " ").last ?? "") {
                position.count.withLock { $0 = count }
            }
            guard command.hasPrefix("go") else { return [] }
            let fen = position.fen.withLock { $0 }
            let fields = fen.split(separator: " ")
            let side = UCI.sideToMove(fen)
            let fullmove = fields.count > 5 ? Int(fields[5]) ?? 1 : 1
            let white = 60 + 10 * ((fullmove - 1) * 2 + (side == .black ? 1 : 0))
            let cp = side == .white ? white : -white
            let moves = legalMoves(fen), count = min(position.count.withLock { $0 }, max(moves.count, 1))
            return (1...Analyzer.targetDepth).flatMap { depth in
                (1...count).map { rank in "info depth \(depth) multipv \(rank) score cp \(cp - 10 * (rank - 1)) pv \(moves.indices.contains(rank - 1) ? moves[rank - 1] : "e2e4")" }
            } + ["bestmove \(moves.first ?? "e2e4")"]
        }
    }

    private static func legalMoves(_ fen: String) -> [String] {
        let squares = (1...8).flatMap { rank in "abcdefgh".map { "\($0)\(rank)" } }
        return squares.flatMap { from in
            Board.targetsFrom(fen, from).map { to, target in from + to + (target.promotion ? "q" : "") }.sorted()
        }
    }
}

/// The last `position` `FakeEngine.climb` was sent, for its next `go`.
private final class LastPosition: Sendable {
    let fen = Mutex("")
    let count = Mutex(1)
}
