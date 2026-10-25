import Foundation

/// A position in the tree: 0 is the main line, other indices alternatives.
/// [] is the starting position; [0, 1] is an alternative at the second ply.
typealias MovePath = [Int]

func lineTo(_ game: ParsedGame, _ path: MovePath) -> [MoveNode] {
    var nodes: [MoveNode] = []
    var list = game.moves
    for index in path {
        guard list.indices.contains(index) else { break }
        let node = list[index]
        nodes.append(node); list = node.children
    }
    return nodes
}
func nodeAt(_ game: ParsedGame, _ path: MovePath) -> MoveNode? {
    guard !path.isEmpty else { return nil }
    let nodes = lineTo(game, path)
    return nodes.count == path.count ? nodes.last : nil
}
func fenAt(_ game: ParsedGame, _ path: MovePath) -> String { nodeAt(game, path)?.fen ?? game.startFen }
func validPath(_ game: ParsedGame, _ path: MovePath) -> Bool { lineTo(game, path).count == path.count }
private func nextMoves(_ game: ParsedGame, _ path: MovePath) -> [MoveNode] {
    path.isEmpty ? game.moves : nodeAt(game, path)?.children ?? []
}
func forward(_ game: ParsedGame, _ path: MovePath) -> MovePath? {
    nextMoves(game, path).isEmpty ? nil : path + [0]
}

/// Shared value-tree mutation. Copies leave the original tree untouched until
/// a save succeeds. The parser uses it to attach variations and annotations.
@discardableResult
func changeMoveList(_ list: inout [MoveNode], at path: MovePath, _ update: (inout [MoveNode]) -> Void) -> Bool {
    guard let index = path.first else { update(&list); return true }
    guard list.indices.contains(index) else { return false }
    return changeMoveList(&list[index].children, at: Array(path.dropFirst()), update)
}

struct GameEdit: Equatable, Sendable {
    var game: ParsedGame
    var path: MovePath
}

/// Extend an ending line, branch in its middle, or visit an existing move.
func playMove(_ game: ParsedGame, _ path: MovePath, _ move: Uci) throws -> GameEdit {
    let list = nextMoves(game, path)
    if let existing = list.firstIndex(where: { $0.uci == move }) {
        return GameEdit(game: game, path: path + [existing])
    }
    let node = try playFrom(fenAt(game, path), move.text)
    var next = game
    changeMoveList(&next.moves, at: path) { $0.append(node) }
    return GameEdit(game: next, path: path + [list.count])
}

/// Remove the move and all continuations, leaving the parent selected.
func deleteFrom(_ game: ParsedGame, _ path: MovePath) -> GameEdit {
    guard let index = path.last else { return GameEdit(game: game, path: path) }
    var next = game
    let parent = Array(path.dropLast())
    changeMoveList(&next.moves, at: parent) { list in
        let at = index < 0 ? max(0, list.count + index) : index
        if list.indices.contains(at) { list.remove(at: at) }
    }
    return GameEdit(game: next, path: parent)
}

/// Promote the last branch off the main line; retain the selected move.
func promoteVariation(_ game: ParsedGame, _ path: MovePath) -> GameEdit {
    guard let at = path.lastIndex(where: { $0 != 0 }) else { return GameEdit(game: game, path: path) }
    var next = game
    changeMoveList(&next.moves, at: Array(path.prefix(at))) { list in
        guard list.indices.contains(path[at]) else { return }
        let moved = list.remove(at: path[at]); list.insert(moved, at: 0)
    }
    return GameEdit(game: next, path: Array(path.prefix(at)) + [0] + path.dropFirst(at + 1))
}
func onMainLine(_ path: MovePath) -> Bool { path.allSatisfy { $0 == 0 } }

/// Empty text clears a note. Closing braces are dropped, not stored as PGN.
func setComment(_ game: ParsedGame, _ path: MovePath, _ text: String) -> ParsedGame {
    var next = game
    let cleaned = cleanPgnText(text.replacingOccurrences(of: "}", with: ""))
    let comment = cleaned.isEmpty ? nil : cleaned
    if nodeAt(game, path) != nil, let index = path.last {
        changeMoveList(&next.moves, at: Array(path.dropLast())) { $0[index].comment = comment }
    } else { next.comment = comment }
    return next
}

/// The starting position cannot change under moves already checked against it.
/// Empty values remove headers; Result falls back to the movetext's *.
func setHeaders(_ game: ParsedGame, _ changes: PgnHeaders) -> ParsedGame {
    var next = game
    for name in changes.names where name != "FEN" && name != "SetUp" {
        let value = changes[name]!.trimmingCharacters(in: .init(charactersIn: Uci.whitespace))
        next.headers[name] = value.isEmpty ? nil : value
    }
    next.headers["Result"] = next.headers["Result"] ?? "*"
    return next
}
