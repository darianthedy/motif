import SwiftUI

enum GamesRoute: Hashable { case collection(String), game(String, String) }
struct GamesHomeView: View {
    @Environment(AppState.self) private var app
    @State private var create = false
    @State private var name = ""
    @State private var renaming: GameCollection?
    @State private var deleting: GameCollection?
    var body: some View {
        // One container for both states so the launch route and alerts stay attached when the first collection lands.
        ZStack {
            if let library = app.store.library, !library.gameCollections.isEmpty {
                List { collections(library) }
            } else {
                EmptyState(title: "No Games Yet", systemImage: "checkerboard.rectangle",
                           description: "Make a collection, then add games as PGN or play them in on the board.",
                           action: .init(title: "New Collection", identifier: "new-game-collection-empty", disabled: !app.store.online) { startCreating() })
            }
        }
        .navigationTitle("Games")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Collection", systemImage: "plus") { startCreating() }
                    .disabled(!app.store.online).accessibilityIdentifier("new-game-collection")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) { AccountButton() }
        }
        .alert("New Collection", isPresented: $create) {
            TextField("Name", text: $name).accessibilityIdentifier("game-collection-name")
            Button("Create") {
                let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !chosen.isEmpty else { return }
                let collection = GameCollection(id: newID(), name: chosen, createdAt: epochMilliseconds())
                Task { if await app.edit({ try await $0.createGameCollections([collection]) }) { app.gamesPath.append(.collection(collection.id)) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Games can be imported as PGN or played in on the board.") }
        .alert("Rename the collection", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { collection in
            TextField("Name", text: $name)
            Button("Save") {
                let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !chosen.isEmpty { Task { _ = await app.edit { try await $0.renameGameCollection(collection.id, chosen) } } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this collection and its games?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { collection in
            Button("Delete Collection", role: .destructive) { Task { _ = await app.edit { try await $0.deleteGameCollection(collection.id) } } }
        }
        .task {
            #if DEBUG
            if let route = app.launchRoute, let first = app.store.library?.gameCollections.first, ["game-collection", "game-add", "game-new", "game-select"].contains(route) { app.gamesPath = [.collection(first.id)] }
            if let route = app.launchRoute, route.hasPrefix("game:") || ["game-details", "game-comment", "game-variation", "game-unreadable"].contains(route), let game = app.store.library?.games.first { app.gamesPath = [.collection(game.collectionId), .game(game.collectionId, game.id)] }
            #endif
        }
    }
    private var subtitle: String {
        guard let library = app.store.library, !library.gameCollections.isEmpty else { return "" }
        return "\(countLabel(library.games.count, "game")) in \(countLabel(library.gameCollections.count, "collection"))"
    }
    private func startCreating() { name = ""; create = true }
    private func collections(_ library: Library) -> some View {
        ForEach(gameCollectionsOf(library), id: \.id) { collection in
            NavigationLink(value: GamesRoute.collection(collection.id)) {
                GameCollectionRow(name: collection.name, count: gamesIn(library, collection.id).count)
            }
            .accessibilityIdentifier("game-collection-" + collection.id)
            .swipeActions {
                Button("Delete", systemImage: "trash") { deleting = collection }.tint(.red).disabled(!app.store.online)
                Button("Rename", systemImage: "pencil") { name = collection.name; renaming = collection }.disabled(!app.store.online)
            }
            .contextMenu {
                Button("Rename…", systemImage: "pencil") { name = collection.name; renaming = collection }.disabled(!app.store.online)
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = collection }.disabled(!app.store.online)
            }
        }
    }
}
private struct GameCollectionRow: View {
    let name: String
    let count: Int
    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: "checkerboard.rectangle", color: .motifAccentStrong)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.body.weight(.medium))
                Text(countLabel(count, "game")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
