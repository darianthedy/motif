import SwiftUI
import UniformTypeIdentifiers

/// ✕ / "Import PGN" / ✓ "Add N": files, clipboard or typed PGN, with what was read.
struct ImportPGNView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let collectionId: String
    @State private var model = AddGamesModel()
    @State private var files = false
    @State private var sourceError: String?
    var body: some View {
        let count = model.read?.games.count ?? 0
        NavigationStack {
            Form {
                Section {
                    Button("Choose Files…", systemImage: "doc") { files = true }
                    Button("Paste From Clipboard", systemImage: "doc.on.clipboard") { paste() }.accessibilityIdentifier("game-import-paste")
                    TextEditor(text: $model.text).autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.asciiCapable).font(.system(.footnote, design: .monospaced)).frame(minHeight: 170).accessibilityIdentifier("game-import-text")
                } header: { Text("Source") } footer: {
                    if let sourceError { Label(sourceError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).accessibilityIdentifier("game-import-source-error") }
                    else { Text("PGN files, or their text pasted above.") }
                }
                if let read = model.read {
                    Section {
                        Label {
                            Text("\(countLabel(read.games.count, "game")) read\(read.errors.isEmpty ? "" : " · \(read.errors.count) couldn't be read")")
                        } icon: {
                            Image(systemName: read.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(read.errors.isEmpty ? Color.motifAccentStrong : .orange)
                        }
                        ForEach(Array(read.errors.enumerated()), id: \.offset) { _, error in Text("Game \(error.game): \(error.message)").font(.footnote).foregroundStyle(.red) }
                        ForEach(Array(read.games.prefix(5).enumerated()), id: \.offset) { _, game in Text(gameTitle(game.headers)) }
                        if read.games.count > 5 { Text("and \(countLabel(read.games.count - 5, "more game"))").foregroundStyle(.secondary) }
                    } header: { Text("Found") } footer: {
                        if !app.store.online { Text("You’re offline. Adding games needs a connection.") }
                    }
                }
            }
            .navigationTitle("Import PGN").navigationBarTitleDisplayMode(.inline)
            .sheetToolbar(confirm: count > 0 ? "Add \(countLabel(count, "Game"))" : "Add",
                          disabled: !app.store.online || count == 0 || model.busy, identifier: "game-import-add",
                          onCancel: { dismiss() }) {
                Task { if await model.add(app, collectionId: collectionId) != nil { dismiss() } }
            }
            .scrollDismissesKeyboard(.interactively).editorKeyboard()
            .fileImporter(isPresented: $files, allowedContentTypes: [.chessPGN, .plainText], allowsMultipleSelection: true) { result in
                do { model.text = try result.get().map(readImportFile).joined(separator: "\n\n"); sourceError = nil }
                catch { sourceError = error.localizedDescription }
            }
        }
    }
    private func paste() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { sourceError = "The clipboard has no text to import."; return }
        model.text = text; sourceError = nil
    }
}
