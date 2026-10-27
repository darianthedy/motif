import Foundation

/// An engine score: centipawns, or mate in N moves. The analyzer keeps scores from
/// White's point of view, so a positive number is good for White.
enum Score: Hashable, Sendable {
    case cp(Int)
    case mate(Int)
}

/// What the bar shows for one position. `final` is set once the search for it has
/// ended on its own (target depth or time) rather than being stopped.
struct Evaluation: Equatable, Sendable {
    let fen: String
    let depth: Int
    let score: Score
    let final: Bool

    /// The side with a forced mate. A position that is already mate (`M0`) has no
    /// sign, so the winner is the side that isn't to move.
    var winner: Side? {
        guard case .mate(let moves) = score else { return nil }
        if moves == 0 { return UCI.sideToMove(fen).opposite }
        return moves > 0 ? .white : .black
    }
}

/// Pure parsing of the engine's UCI output. Only what the bar needs is kept: the
/// depth, an exact score and the first move of the principal variation, plus the
/// end of a search.
enum UCI {
    enum Line: Equatable, Sendable {
        /// An exact score, as UCI gives it: from the side to move's point of view
        /// unless it came through `parse(_:fen:)`.
        case info(depth: Int, score: Score, move: String?)
        case bestmove(String)
    }

    /// Engine point of view. Nil for anything the analyzer doesn't use: `info string`,
    /// `currmove` updates, lines without a depth or a score, and bound scores from an
    /// aspiration window that failed high or low.
    static func parse(_ line: String) -> Line? {
        let words = line.split(separator: " ").map(String.init)
        guard let head = words.first else { return nil }
        if head == "bestmove" { return words.count > 1 ? .bestmove(words[1]) : nil }
        guard head == "info", words.count > 1, words[1] != "string" else { return nil }
        var depth: Int?, score: Score?, move: String?, index = 1
        while index < words.count {
            switch words[index] {
            case "depth":
                depth = words.indices.contains(index + 1) ? Int(words[index + 1]) : nil
                index += 2
            case "score":
                guard words.indices.contains(index + 2), let value = Int(words[index + 2]) else { return nil }
                switch words[index + 1] {
                case "cp": score = .cp(value)
                case "mate": score = .mate(value)
                default: return nil
                }
                index += 3
            case "lowerbound", "upperbound":
                return nil
            case "pv":
                move = words.indices.contains(index + 1) ? words[index + 1] : nil
                index = words.count
            default:
                index += 1
            }
        }
        guard let depth, let score else { return nil }
        return .info(depth: depth, score: score, move: move)
    }

    /// White's point of view for the position `fen`.
    static func parse(_ line: String, fen: String) -> Line? {
        guard case .info(let depth, let score, let move)? = parse(line) else { return parse(line) }
        return .info(depth: depth, score: whiteView(score, sideToMove(fen)), move: move)
    }

    /// UCI scores belong to the side to move; flip them when that's Black.
    static func whiteView(_ score: Score, _ side: Side) -> Score {
        guard side == .black else { return score }
        switch score {
        case .cp(let value): return .cp(-value)
        case .mate(let moves): return .mate(-moves)
        }
    }

    /// The FEN's second field, without loading the board.
    static func sideToMove(_ fen: String) -> Side {
        fen.split(separator: " ").dropFirst().first == "b" ? .black : .white
    }
}
