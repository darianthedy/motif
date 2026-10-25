import SwiftUI
struct PuzzlesHomeView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        List {
            if let library = app.store.library {
                if library.collections.isEmpty { Text("No puzzles here yet.").foregroundStyle(.secondary) }
                ForEach(collectionsOf(library), id: \.id) { collection in
                    LabeledContent(collection.name, value: "\(puzzlesIn(library, collection.id).count) puzzles")
                }
            }
        }.navigationTitle("Puzzles")
    }
}
