import SwiftUI
struct CollectionView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let collectionId: String
    @State private var rename = false
    @State private var name = ""
    @State private var deletion = false
    var body: some View {
        Group {
            if let library = app.store.library, let collection = library.collections.first(where: { $0.id == collectionId }) {
                let puzzles = puzzlesIn(library, collectionId), stats = statsFor(puzzles.map(\.id), puzzleRecords(library.attempts))
                List {
                    Text("\(stats.total) puzzles · \(stats.solved) solved · \(stats.failed) to review · \(stats.unseen) new").font(.footnote).foregroundStyle(.secondary)
                    if let run = runIn(library, collectionId), let current = progressOf(library, run).current, !current.isEmpty {
                        Section("Session in progress") {
                            Text("\(progressOf(library, run).remaining) left")
                            Button("Resume") { app.session = SessionRoute(scope: collectionId) }.accessibilityIdentifier("resume-session")
                            Button("Discard", role: .destructive) { Task { _ = await app.edit { try await $0.deleteRun(run.id) } } }.disabled(!app.store.online)
                        }
                    }
                    Section {
                        Button("Solve in order") { Task { await app.begin(collectionId, .ordered, puzzles.map(\.id)) } }.accessibilityIdentifier("solve-ordered")
                        Button("Solve shuffled") { Task { await app.begin(collectionId, .randomInCollection, puzzles.map(\.id)) } }
                        NavigationLink("Browse puzzles", value: PuzzleRoute.puzzles(collectionId)).accessibilityIdentifier("browse-puzzles")
                    }.disabled(puzzles.isEmpty)
                    Section {
                        Button("Rename collection") { name = collection.name; rename = true }.disabled(!app.store.online)
                        Button("Delete collection", role: .destructive) { deletion = true }.disabled(!app.store.online)
                        OfflineNote()
                    }
                }.navigationTitle(collection.name)
            } else { Color.clear.onAppear { dismiss() } }
        }.toolbar(.hidden, for: .tabBar)
            .alert("Rename the collection", isPresented: $rename) {
                TextField("Name", text: $name)
                Button("Save") {
                    let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chosen.isEmpty { Task { _ = await app.edit { try await $0.renameCollection(collectionId, chosen) } } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this collection and its puzzles?", isPresented: $deletion, titleVisibility: .visible) {
                Button("Delete collection", role: .destructive) { Task { if await app.edit({ try await $0.deleteCollection(collectionId) }) { app.puzzlesPath = [] } } }
            }
    }
}
