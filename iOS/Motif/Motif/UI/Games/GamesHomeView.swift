import SwiftUI
struct GamesHomeView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        List {
            if let library = app.store.library {
                if library.gameCollections.isEmpty { Text("No games here yet.").foregroundStyle(.secondary) }
                ForEach(library.gameCollections, id: \.id) { collection in Text(collection.name) }
            }
        }.navigationTitle("Games")
    }
}
