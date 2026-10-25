import SwiftUI
struct CollectionView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let collectionId: String
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
                    }.disabled(puzzles.isEmpty)
                    OfflineNote()
                }.navigationTitle(collection.name)
            } else { Color.clear.onAppear { dismiss() } }
        }
    }
}
