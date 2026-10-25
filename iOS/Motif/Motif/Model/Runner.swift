/// Wrong tries on one ply before the answer is shown.
let ATTEMPTS_BEFORE_HINT = 3
/// Pause before the reply so the move is seen; measured in the trainer.
let REPLY_MS = 450

enum MoveOutcome: Equatable, Sendable {
    /// Reply and finished are independent; a final forced reply still plays.
    case correct(reply: Uci?, finished: Bool)
    /// Legal on the board but not accepted. Revert; the attempt stays failed.
    case wrong
}

enum PuzzleResult: String, Codable, Sendable { case solved, failed }

/// The ply counts accepted solver moves, not intervening opponent replies.
struct Miss: Hashable, Codable, Sendable {
    var ply: Int
    var move: Uci
}

/// Validates continuations, not chess legality. Illegal gestures never reach
/// submit, so they cost nothing; a legal wrong move permanently fails the run.
final class PuzzleRunner {
    let puzzle: Puzzle
    private var node: TrieNode
    private(set) var accepted: [Uci] = []
    private(set) var misses: [Miss] = []
    private(set) var wrongAtThisPly = 0
    private(set) var complete = false
    private(set) var hinted = false

    init(_ puzzle: Puzzle) {
        self.puzzle = puzzle
        node = buildTrie(puzzle.solutions)
    }

    var mistakes: Int { misses.count }
    var clean: Bool { mistakes == 0 }
    var result: PuzzleResult { clean ? .solved : .failed }
    var shouldRevealHint: Bool { wrongAtThisPly >= ATTEMPTS_BEFORE_HINT }

    /// Reading the revealed answer records that a hint was used.
    func revealHint() -> Uci? {
        guard shouldRevealHint, let move = node.preferredMove else { return nil }
        hinted = true
        return move
    }

    @discardableResult
    func submit(_ move: Uci) -> MoveOutcome {
        guard !complete else { return .wrong }
        guard let edge = findEdge(node, move) else {
            wrongAtThisPly += 1
            misses.append(Miss(ply: accepted.count, move: move))
            return .wrong
        }
        node = edge.next
        accepted.append(move)
        wrongAtThisPly = 0
        complete = isTerminal(node)
        return .correct(reply: edge.reply, finished: complete)
    }
}

enum PlacementOutcome: Equatable, Sendable { case correct, wrong }

/// Only a completed square-and-piece guess reaches submit. Choosing a square
/// or cancelling the picker is free, just like cancelling a promotion.
final class MissingPieceRunner {
    let puzzle: Puzzle
    let answer: Placement
    private(set) var wrongGuesses: [Placement] = []
    private(set) var complete = false
    private(set) var hinted = false

    init(_ puzzle: Puzzle, _ answer: Placement) {
        self.puzzle = puzzle
        self.answer = answer
    }

    var mistakes: Int { wrongGuesses.count }
    var clean: Bool { mistakes == 0 }
    var result: PuzzleResult { clean ? .solved : .failed }
    var shouldRevealHint: Bool { mistakes >= ATTEMPTS_BEFORE_HINT }

    func revealHint() -> Placement? {
        guard shouldRevealHint else { return nil }
        hinted = true
        return answer
    }

    @discardableResult
    func submit(_ square: String, _ type: PieceType) -> PlacementOutcome {
        guard !complete else { return .wrong }
        let guess = Placement(color: answer.color, type: type, square: square)
        guard samePlacement(guess, answer) else {
            wrongGuesses.append(guess)
            return .wrong
        }
        complete = true
        return .correct
    }
}
