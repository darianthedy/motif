import SwiftUI
struct CollectionView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    let collectionId: String
    @State private var rename = false
    @State private var name = ""
    @State private var deletion = false
    @State private var importing = false
    var body: some View {
        Group {
            if let library = app.store.library, let collection = library.collections.first(where: { $0.id == collectionId }) {
                let puzzles = puzzlesIn(library, collectionId)
                ZStack {
                    if puzzles.isEmpty {
                        EmptyState(title: "No Puzzles", systemImage: "puzzlepiece",
                                   description: "Import puzzles into this collection to start solving.",
                                   action: .init(title: "Import Puzzles", identifier: "import-into-collection-empty", disabled: !app.store.online) { importing = true })
                            .readableWidth()
                    } else {
                        List {
                            Section { StatsCard(stats: statsFor(puzzles.map(\.id), puzzleRecords(library.attempts))) }
                            if let run = runIn(library, collectionId), let current = progressOf(library, run).current, !current.isEmpty {
                                session(remaining: progressOf(library, run).remaining, run: run)
                            }
                            Section("Solve") {
                                Button { Task { await app.begin(collectionId, .ordered, puzzles.map(\.id)) } } label: {
                                    Label("Solve in Order", systemImage: "list.number")
                                }.accessibilityIdentifier("solve-ordered")
                                Button { Task { await app.begin(collectionId, .randomInCollection, puzzles.map(\.id)) } } label: {
                                    Label("Solve Shuffled", systemImage: "shuffle")
                                }.accessibilityIdentifier("solve-shuffled")
                            }
                            Section {
                                NavigationLink(value: PuzzleRoute.puzzles(collectionId)) {
                                    LabeledContent { Text("\(puzzles.count)") } label: { Label("All Puzzles", systemImage: "square.grid.2x2") }
                                }.accessibilityIdentifier("browse-puzzles")
                            }
                        }
                    }
                }
                .navigationTitle(collection.name)
                // Large when pushed from the home list; inline as the detail column beside it (§6.5).
                .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .automatic)
                // Each item sets a flag; the alert, dialog and sheet hang off the screen, not the menu (F15).
                .motifOverflowMenu("More", identifier: "collection-actions") {
                    Button("Rename…", systemImage: "pencil") { name = collection.name; rename = true }.disabled(!app.store.online)
                    Button("Import Into Collection…", systemImage: "square.and.arrow.down") { importing = true }.disabled(!app.store.online)
                    Divider()
                    Button("Delete Collection", systemImage: "trash", role: .destructive) { deletion = true }.disabled(!app.store.online)
                }
            } else { Color.clear.onAppear { dismiss() } }
        }
            .alert("Rename the collection", isPresented: $rename) {
                TextField("Name", text: $name)
                Button("Save") {
                    let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chosen.isEmpty { Task { _ = await app.edit { try await $0.renameCollection(collectionId, chosen) } } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this collection and its puzzles?", isPresented: $deletion, titleVisibility: .visible) {
                Button("Delete Collection", role: .destructive) { Task { if await app.edit({ try await $0.deleteCollection(collectionId) }) { app.openPuzzles([]) } } }
            }
            .sheet(isPresented: $importing) { ImportView(collectionId: collectionId).environment(app) }
    }
    private func session(remaining: Int, run: Run) -> some View {
        SessionRow(remaining: remaining, online: app.store.online,
                   resume: { app.session = SessionRoute(scope: collectionId) },
                   discard: { Task { _ = await app.edit { try await $0.deleteRun(run.id) } } })
    }
}
