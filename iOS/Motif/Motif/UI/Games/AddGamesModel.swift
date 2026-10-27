import SwiftUI

/// Shared by the Import PGN and New Game sheets.
@Observable @MainActor final class AddGamesModel {
    var text = "" { didSet { read = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : parsePgnFile(text) } }
    var fen = ""
    var busy = false
    private(set) var read: PgnFile?
    var start: String { let trimmed = fen.trimmingCharacters(in: .whitespacesAndNewlines); return trimmed.isEmpty ? Board.defaultPosition : trimmed }
    var fenCheck: Board.FenValidation { Board.validateFen(start) }
    func add(_ app: AppState, collectionId: String, newBoard: Bool = false) async -> String? {
        guard app.store.online, !busy, let library = app.store.library else { return nil }
        var content: [GameContent]
        if newBoard {
            guard fenCheck.ok else { return nil }
            content = [GameContent(pgn: writePgn(newGame(start)), orientation: Board.turnOf(start) ?? .white)]
        } else { content = (read?.games ?? []).map { GameContent(pgn: writePgn($0), orientation: .white) } }
        guard !content.isEmpty else { return nil }
        busy = true; defer { busy = false }
        let games = appendGames(library, collectionId, content)
        if await app.edit({ try await $0.addGames(games) }, done: newBoard ? nil : "Added \(games.count) \(games.count == 1 ? "game" : "games").") { return games.first?.id }
        return nil
    }
}
