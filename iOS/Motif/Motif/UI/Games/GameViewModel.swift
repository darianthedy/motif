import Foundation
import Observation

/// PGN is the stored representation. Edits build a local draft, offline too,
/// that only reaches the backend when the user saves it.
@Observable @MainActor final class GameViewModel {
    let id: String
    private(set) var tree: ParsedGame?
    private(set) var path: MovePath = []
    private(set) var orientation: Side
    private(set) var saving = false
    var online: Bool
    var problem: String?
    @ObservationIgnored private var stored: Game
    private var savedTree: ParsedGame?
    private var savedOrientation: Side
    @ObservationIgnored private let saveChanges: @MainActor (GameChanges) async -> Bool
    init(_ game: Game, online: Bool = true, save: @escaping @MainActor (GameChanges) async -> Bool) {
        id = game.id; stored = game; tree = try? parsePgn(game.pgn); orientation = game.orientation; self.online = online; saveChanges = save
        savedTree = tree; savedOrientation = orientation
    }
    var unsaved: Bool { tree != savedTree || orientation != savedOrientation }
    var canSave: Bool { online && unsaved && !saving }
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
        if !unsaved && !saving { revert() }
    }
    func go(_ path: MovePath) { self.path = tree.map { validPath($0, path) ? path : [] } ?? [] }
    func back() { go(Array(path.dropLast())) }
    func next() { if let tree, let next = forward(tree, path) { go(next) } }
    func end() { guard let tree else { return }; var last = path; while let next = forward(tree, last) { last = next }; go(last) }
    func play(_ move: Uci) {
        guard let tree else { return }
        do {
            let edit = try playMove(tree, path, move)
            path = edit.path
            if edit.game != tree { change(edit.game) }
        } catch { problem = String(describing: error) }
    }
    func deleteHere() {
        guard let tree, node != nil else { return }
        let edit = deleteFrom(tree, path); path = edit.path; change(edit.game)
    }
    func promote() {
        guard let tree, !onMainLine(path) else { return }
        let edit = promoteVariation(tree, path); path = edit.path; change(edit.game)
    }
    func comment(_ text: String) { guard let tree else { return }; change(setComment(tree, path, text)) }
    func details(_ changes: PgnHeaders) { guard let tree else { return }; change(setHeaders(tree, changes)) }
    func flip() { orientation = orientation.opposite }
    /// Upload the draft; on failure it stays unsaved so the user can retry or discard.
    @discardableResult func save() async -> Bool {
        guard canSave, let tree else { return false }
        var changes = GameChanges()
        if tree != savedTree { changes.pgn = writePgn(tree) }
        if orientation != savedOrientation { changes.orientation = orientation }
        // Edits made while the upload runs stay unsaved.
        let side = orientation
        saving = true; defer { saving = false }
        guard await saveChanges(changes) else { return false }
        savedTree = tree; savedOrientation = side
        return true
    }
    /// Drop the draft and return to the stored copy.
    func discard() { revert() }
    private func change(_ next: ParsedGame) { tree = next; problem = nil }
    private func revert() {
        tree = try? parsePgn(stored.pgn); orientation = stored.orientation
        savedTree = tree; savedOrientation = orientation; normalizePath()
    }
    private func normalizePath() { if let tree, !validPath(tree, path) { path = [] } }
}
