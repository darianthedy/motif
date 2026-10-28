import ChessKitEngine
import Foundation

/// `UCIEngine` over ChessKitEngine's Stockfish. One per app: the engine starts the
/// first time `shared` is used (when a game screen first opens) and then stays, because
/// ChessKitEngine moves the process's stdout onto its pipe and a stopped engine leaves
/// stdout writing into a closed one. Commands sent before Stockfish is ready wait for it.
///
/// ChessKitEngine hands out parsed responses rather than text, so they are written back
/// as UCI lines; the analyzer parses every engine the same way.
final class StockfishEngine: UCIEngine {
    static let shared = StockfishEngine()

    /// Transposition table size, in MB.
    static let hash = 128

    private let output = LineBroadcast()
    private let commands: AsyncStream<String>.Continuation

    private init() {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        commands = continuation
        Task.detached(priority: .userInitiated) { [output] in await Self.run(stream, output) }
    }

    var lines: AsyncStream<String> { output.subscribe() }

    func send(_ command: String) { commands.yield(command) }

    /// Starts Stockfish, waits for ChessKitEngine's setup (nets, threads, MultiPV) to
    /// finish, then forwards commands in order for the life of the app.
    private static func run(_ commands: AsyncStream<String>, _ output: LineBroadcast) async {
        let engine = Stockfish.makeEngine()
        // ChessKitEngine sets Threads to one less than the core count it's given.
        await engine.start(coreCount: ProcessInfo.processInfo.activeProcessorCount, multipv: 1)
        guard let responses = await engine.responseStream else { return }
        let (ready, readied) = AsyncStream.makeStream(of: Void.self)
        let reading = Task {
            var waiting = true
            for await response in responses {
                // The first readyok is yielded after ChessKitEngine has sent its setup options.
                if waiting, response == .readyok { waiting = false; readied.finish() }
                if let text = line(for: response) { output.yield(text) }
            }
        }
        for await _ in ready {}
        await engine.send(command: .setoption(id: "Hash", value: "\(hash)"))
        var threads = coolThreads
        for await text in commands {
            // The analyzer only sends go to an idle engine, so this is a safe moment.
            if text.hasPrefix("go"), threads != Self.threads {
                threads = Self.threads
                await engine.send(command: .setoption(id: "Threads", value: "\(threads)"))
            }
            if let parsed = command(text) { await engine.send(command: parsed) }
        }
        reading.cancel()
    }

    /// Active cores − 1, or 1 once the device runs hot.
    private static var threads: Int {
        ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue ? 1 : coolThreads
    }

    private static var coolThreads: Int { max(ProcessInfo.processInfo.activeProcessorCount - 1, 1) }

    /// The UCI commands the analyzer sends, as ChessKitEngine values.
    static func command(_ text: String) -> EngineCommand? {
        let words = text.split(separator: " ").map(String.init)
        func number(after key: String) -> Int? {
            guard let index = words.firstIndex(of: key), words.indices.contains(index + 1) else { return nil }
            return Int(words[index + 1])
        }
        switch words.first ?? "" {
        case "stop": return .stop
        case "isready": return .isready
        case "ucinewgame": return .ucinewgame
        case "position":
            let end = words.firstIndex(of: "moves") ?? words.endIndex
            let moves = end < words.endIndex ? Array(words[(end + 1)...]) : nil
            if words.count > 1, words[1] == "startpos" { return .position(.startpos, moves: moves) }
            guard words.count > 2, words[1] == "fen" else { return nil }
            return .position(.fen(words[2..<end].joined(separator: " ")), moves: moves)
        case "go":
            return .go(depth: number(after: "depth"), nodes: number(after: "nodes"),
                       movetime: number(after: "movetime"), infinite: words.contains("infinite"))
        case "setoption":
            guard let name = words.firstIndex(of: "name") else { return nil }
            let value = words.firstIndex(of: "value")
            let id = words[(name + 1)..<(value ?? words.endIndex)].joined(separator: " ")
            return .setoption(id: id, value: value.map { words[($0 + 1)...].joined(separator: " ") })
        default: return nil
        }
    }

    /// A ChessKitEngine response as the UCI line Stockfish printed.
    static func line(for response: EngineResponse) -> String? {
        switch response {
        case .uciok: return "uciok"
        case .readyok: return "readyok"
        case .id: return nil
        case let .bestmove(move, ponder): return "bestmove \(move)" + (ponder.map { " ponder \($0)" } ?? "")
        case let .info(info):
            if let string = info.string { return "info string \(string)" }
            var words = ["info"]
            if let depth = info.depth { words += ["depth", "\(depth)"] }
            if let multipv = info.multipv { words += ["multipv", "\(multipv)"] }
            if let score = info.score {
                if let mate = score.mate { words += ["score", "mate", "\(mate)"] }
                else if let cp = score.cp { words += ["score", "cp", "\(Int(cp.rounded()))"] }
                if score.lowerbound == true { words.append("lowerbound") }
                if score.upperbound == true { words.append("upperbound") }
            }
            if let pv = info.pv, !pv.isEmpty { words += ["pv"] + pv }
            return words.joined(separator: " ")
        }
    }
}
