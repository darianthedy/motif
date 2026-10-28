import SwiftUI

/// Saves an analysis that isn't in the library as a new game, into an existing
/// collection or a new one.
struct SaveAsGameSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let content: GameContent
    /// Empty for a new collection.
    @State private var collectionId = ""
    @State private var name = "Puzzles"
    @State private var busy = false
    private var collections: [GameCollection] { app.store.library.map(gameCollectionsOf) ?? [] }
    private var chosenName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Collection", selection: $collectionId) {
                        Text("New Collection").tag("")
                        ForEach(collections, id: \.id) { Text($0.name).tag($0.id) }
                    }.pickerStyle(.menu).accessibilityIdentifier("save-game-collection")
                    if collectionId.isEmpty { TextField("Collection name", text: $name).accessibilityIdentifier("save-game-collection-name") }
                } header: { Text("Add to") } footer: {
                    if !app.store.online { Text("You’re offline. Saving needs a connection.") }
                }
            }
            .navigationTitle("Save as Game").navigationBarTitleDisplayMode(.inline)
            .sheetToolbar(confirm: "Save Game", disabled: !app.store.online || busy || (collectionId.isEmpty && chosenName.isEmpty),
                          identifier: "save-game-confirm", onCancel: { dismiss() }) { Task { await save() } }
            .onAppear { if collectionId.isEmpty, let first = collections.first { collectionId = first.id } }
        }
    }
    private func save() async {
        guard let library = app.store.library, !busy else { return }
        busy = true; defer { busy = false }
        let created = collectionId.isEmpty ? GameCollection(id: newID(), name: chosenName, createdAt: epochMilliseconds()) : nil
        let target = created?.id ?? collectionId
        let games = appendGames(library, target, [content])
        let label = created?.name ?? collections.first { $0.id == target }?.name ?? "Games"
        let saved = await app.edit({
            if let created { try await $0.createGameCollections([created]) }
            try await $0.addGames(games)
        }, done: "Saved to \(label).")
        if saved { dismiss() }
    }
}
