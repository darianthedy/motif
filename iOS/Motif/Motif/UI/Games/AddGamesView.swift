import SwiftUI
import UniformTypeIdentifiers
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
struct AddGamesView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let collectionId: String
    @State private var model = AddGamesModel()
    @State private var files = false
    var body: some View {
        NavigationStack {
            Form {
                Section("PGN files or pasted PGN") {
                    Button("Choose files") { files = true }
                    TextEditor(text: $model.text).autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.asciiCapable).font(.system(.footnote, design: .monospaced)).frame(minHeight: 170).accessibilityIdentifier("game-import-text")
                }
                if let read = model.read {
                    Section {
                        Text("\(countLabel(read.games.count, "game")) read\(read.errors.isEmpty ? "" : " · \(read.errors.count) couldn't be read")")
                        ForEach(Array(read.errors.enumerated()), id: \.offset) { _, error in Text("game \(error.game): \(error.message)").font(.footnote).foregroundStyle(.red) }
                        if read.games.count <= 5 { ForEach(Array(read.games.enumerated()), id: \.offset) { _, game in Text(gameTitle(game.headers)) } }
                        Button("Add \(countLabel(read.games.count, "game"))") { add(false) }.disabled(!app.store.online || read.games.isEmpty || model.busy).accessibilityIdentifier("game-import-add")
                    }
                }
                Section("Or play one in") {
                    TextField("Starting position (FEN), if not the usual one", text: $model.fen, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("game-start-fen")
                    if !model.fenCheck.ok { Text(model.fenCheck.error ?? "Invalid FEN").foregroundStyle(.red).font(.footnote) }
                    Button("New game on the board") { add(true) }.disabled(!model.fenCheck.ok || !app.store.online || model.busy).accessibilityIdentifier("game-new-board")
                }
                OfflineNote()
            }.navigationTitle("Add games").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively).editorKeyboard()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .fileImporter(isPresented: $files, allowedContentTypes: [.chessPGN, .plainText], allowsMultipleSelection: true) { result in
                    do { model.text = try result.get().map(readImportFile).joined(separator: "\n\n") }
                    catch { app.notice = error.localizedDescription }
                }
        }
    }
    private func add(_ newBoard: Bool) {
        Task {
            if let id = await model.add(app, collectionId: collectionId, newBoard: newBoard) {
                dismiss()
                if newBoard { app.gamesPath.append(.game(collectionId, id)) }
            }
        }
    }
}
