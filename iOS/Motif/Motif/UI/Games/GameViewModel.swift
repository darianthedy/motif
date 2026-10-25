import Foundation
import Observation

/// PGN is the stored representation. A visible draft lets rapid edits build
/// on one another while the immutable save snapshots upload in order.
@Observable @MainActor final class GameViewModel {
    let id: String
    private(set) var tree: ParsedGame?
    private(set) var path: MovePath = []
    private(set) var orientation: Side
    private(set) var pending = 0
    var online: Bool
    var problem: String?
    @ObservationIgnored private var stored: Game
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private let saveChanges: @MainActor (GameChanges) async -> Bool
    init(_ game: Game, online: Bool = true, save: @escaping @MainActor (GameChanges) async -> Bool) {
        id = game.id; stored = game; tree = try? parsePgn(game.pgn); orientation = game.orientation; self.online = online; saveChanges = save
    }
    var fen: String { tree.map { fenAt($0, path) } ?? Board.defaultPosition }
    var node: MoveNode? { tree.flatMap { nodeAt($0, path) } }
    var following: [MoveNode] { node?.children ?? (path.isEmpty ? tree?.moves ?? [] : []) }
    var comment: String {
        if let node { return [displayComment(node.before), displayComment(node.comment)].filter { !$0.isEmpty }.joined(separator: " ") }
        return displayComment(tree?.comment)
    }
    var currentName: String { guard let tree, let node else { return "Note on the game" }; return "\(moveNumber(fenAt(tree, Array(path.dropLast())), true) ?? "") \(node.san)" }
    func receive(_ game: Game) {
        stored = game
        if pending == 0 { tree = try? parsePgn(game.pgn); orientation = game.orientation; normalizePath() }
    }
    func go(_ path: MovePath) { self.path = tree.map { validPath($0, path) ? path : [] } ?? [] }
    func back() { go(Array(path.dropLast())) }
    func next() { if let tree, let next = forward(tree, path) { go(next) } }
    func end() { guard let tree else { return }; var last = path; while let next = forward(tree, last) { last = next }; go(last) }
    func play(_ move: Uci) {
        guard online, let tree else { return }
        do {
            let edit = try playMove(tree, path, move)
            path = edit.path
            if edit.game != tree { save(edit.game) }
        } catch { problem = String(describing: error) }
    }
    func deleteHere() {
        guard online, let tree, node != nil else { return }
        let edit = deleteFrom(tree, path); path = edit.path; save(edit.game)
    }
    func promote() {
        guard online, let tree, !onMainLine(path) else { return }
        let edit = promoteVariation(tree, path); path = edit.path; save(edit.game)
    }
    func comment(_ text: String) { guard online, let tree else { return }; save(setComment(tree, path, text)) }
    func details(_ changes: PgnHeaders) { guard online, let tree else { return }; save(setHeaders(tree, changes)) }
    func flip() {
        guard online else { return }; orientation = orientation.opposite
        enqueue(GameChanges(orientation: orientation))
    }
    private func save(_ next: ParsedGame) { tree = next; problem = nil; enqueue(GameChanges(pgn: writePgn(next))) }
    private func normalizePath() { if let tree, !validPath(tree, path) { path = [] } }
    private func enqueue(_ changes: GameChanges) {
        pending += 1
        let preceding = saving
        saving = Task { [weak self, saveChanges] in
            await preceding?.value
            let saved = await saveChanges(changes)
            guard let self else { return }
            self.pending -= 1
            if self.pending == 0 {
                if !saved { self.tree = try? parsePgn(self.stored.pgn); self.orientation = self.stored.orientation; self.normalizePath() }
            }
        }
    }
    func waitForSaves() async { await saving?.value }
}
