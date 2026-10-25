import SwiftUI

enum GamesRoute: Hashable { case collection(String), game(String, String) }
struct GamesHomeView: View {
    @Environment(AppState.self) private var app
    @State private var create = false
    @State private var name = ""
    var body: some View {
        List {
            if let library = app.store.library {
                Section {
                    if library.gameCollections.isEmpty { Text("Nothing here yet. Make a collection, then add games as PGN or play them in on the board.").foregroundStyle(.secondary) }
                    else { Text("\(library.games.count) games in \(library.gameCollections.count) collections").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(gameCollectionsOf(library), id: \.id) { collection in
                        NavigationLink(value: GamesRoute.collection(collection.id)) {
                            VStack(alignment: .leading) { Text(collection.name); Text("\(gamesIn(library, collection.id).count) games").font(.footnote).foregroundStyle(.secondary) }
                        }.accessibilityIdentifier("game-collection-" + collection.id)
                    }
                }
            }
            Section {
                Button("New collection") { name = ""; create = true }.disabled(!app.store.online).accessibilityIdentifier("new-game-collection")
                OfflineNote()
            }
        }.navigationTitle("Games")
            .alert("Name the collection", isPresented: $create) {
                TextField("Name", text: $name).accessibilityIdentifier("game-collection-name")
                Button("Create") {
                    let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !chosen.isEmpty else { return }
                    let collection = GameCollection(id: newID(), name: chosen, createdAt: epochMilliseconds())
                    Task { if await app.edit({ try await $0.createGameCollections([collection]) }) { app.gamesPath.append(.collection(collection.id)) } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .task {
                #if DEBUG
                if let route = app.launchRoute, let first = app.store.library?.gameCollections.first, ["game-collection", "game-add"].contains(route) { app.gamesPath = [.collection(first.id)] }
                #endif
            }
    }
}
