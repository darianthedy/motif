import SwiftUI

enum GameCollectionMode: String, CaseIterable { case browse, select, reorder }
@Observable @MainActor final class GameCollectionModel {
    var mode = GameCollectionMode.browse { didSet { selected = [] } }
    var query = ""
    var selected: Set<String> = []
    var target = ""
    func shown(_ games: [Game]) -> [Game] { mode == .reorder ? games : games.filter { matchesSearch(readHeaders($0.pgn), query) } }
    func toggle(_ id: String) { if !selected.insert(id).inserted { selected.remove(id) } }
    func bulk(_ app: AppState, games: [Game], target: String, copy: Bool) async -> Bool {
        guard app.store.online, let library = app.store.library else { return false }
        let chosen = games.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return false }
        let saved: Bool
        if copy {
            let added = copyGames(library, chosen, target)
            saved = await app.edit({ try await $0.addGames(added) }, done: "Copied \(added.count) games.")
        } else {
            let placements = moveGames(library, chosen, target)
            saved = await app.edit({ try await $0.placeGames(placements) }, done: "Moved \(placements.count) games.")
        }
        if saved { mode = .browse }; return saved
    }
}
struct GameCollectionView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let collectionId: String
    @State private var model = GameCollectionModel()
    @State private var adding = false
    @State private var renaming = false
    @State private var name = ""
    @State private var deletingCollection = false
    @State private var deletingGames = false
    var body: some View {
        Group {
            if let library = app.store.library, let collection = library.gameCollections.first(where: { $0.id == collectionId }) {
                collectionContent(collection, library: library)
            } else { Color.clear.onAppear { dismiss() } }
        }.toolbar(.hidden, for: .tabBar)
            .sheet(isPresented: $adding) { AddGamesView(collectionId: collectionId).environment(app) }
            .alert("Rename the collection", isPresented: $renaming) {
                TextField("Name", text: $name)
                Button("Save") {
                    let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chosen.isEmpty { Task { _ = await app.edit { try await $0.renameGameCollection(collectionId, chosen) } } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this collection and its games?", isPresented: $deletingCollection, titleVisibility: .visible) {
                Button("Delete collection", role: .destructive) { Task { if await app.edit({ try await $0.deleteGameCollection(collectionId) }) { app.gamesPath = [] } } }
            }
            .confirmationDialog("Delete the selected games?", isPresented: $deletingGames, titleVisibility: .visible) {
                Button("Delete games", role: .destructive) {
                    let ids = Array(model.selected)
                    Task { if await app.edit({ try await $0.deleteGames(ids) }, done: "Deleted \(ids.count) games.") { model.mode = .browse } }
                }
            }
            .task {
                #if DEBUG
                if app.launchRoute == "game-add" { adding = true }
                #endif
            }
    }
    private func collectionContent(_ collection: GameCollection, library: Library) -> some View {
        let games = gamesIn(library, collectionId), chosen = games.filter { model.selected.contains($0.id) }
        return List {
            Section {
                Text("\(games.count) games").font(.footnote).foregroundStyle(.secondary)
                if model.mode == .browse { Button("Add games") { adding = true }.disabled(!app.store.online).accessibilityIdentifier("add-games") }
                Picker("Mode", selection: $model.mode) {
                    Text("Browse").tag(GameCollectionMode.browse)
                    Text("Select").tag(GameCollectionMode.select).disabled(!app.store.online)
                    Text("Reorder").tag(GameCollectionMode.reorder).disabled(!app.store.online)
                }.pickerStyle(.segmented)
                if model.mode != .reorder { TextField("Search players, event, opening…", text: $model.query).accessibilityIdentifier("game-search") }
            }
            if model.mode == .select { bulkControls(collection, library: library, games: games, chosen: chosen) }
            Section {
                if model.shown(games).isEmpty { Text(games.isEmpty ? "No games yet." : "No game matches.").foregroundStyle(.secondary) }
                ForEach(model.shown(games), id: \.id) { game in
                    if model.mode == .browse {
                        NavigationLink(value: GamesRoute.game(collectionId, game.id)) { gameLabel(game) }.accessibilityIdentifier("game-row-" + game.id)
                    } else if model.mode == .select {
                        Button { model.toggle(game.id) } label: { HStack { Image(systemName: model.selected.contains(game.id) ? "checkmark.square.fill" : "square"); gameLabel(game) } }.buttonStyle(.plain)
                    } else {
                        HStack {
                            gameLabel(game); Spacer()
                            Button { shift(game, .up, library) } label: { Image(systemName: "arrow.up") }.disabled(!app.store.online || games.first?.id == game.id).accessibilityLabel("Move up")
                            Button { shift(game, .down, library) } label: { Image(systemName: "arrow.down") }.disabled(!app.store.online || games.last?.id == game.id).accessibilityLabel("Move down")
                        }.buttonStyle(.borderless)
                    }
                }
            }
            Section {
                ShareLink(item: PGNExport(text: gamesAsFile(games), name: collection.name), preview: SharePreview(collection.name)) { Label("Export collection as PGN", systemImage: "square.and.arrow.up") }.disabled(games.isEmpty)
                Button("Rename collection") { name = collection.name; renaming = true }.disabled(!app.store.online)
                Button("Delete collection", role: .destructive) { deletingCollection = true }.disabled(!app.store.online)
                OfflineNote()
            }
        }.navigationTitle(collection.name)
    }
    private func gameLabel(_ game: Game) -> some View {
        let headers = readHeaders(game.pgn), subtitle = gameSubtitle(headers)
        return VStack(alignment: .leading, spacing: 4) { Text(gameTitle(headers)).lineLimit(2); if !subtitle.isEmpty { Text(subtitle).font(.footnote).foregroundStyle(.secondary) } }
    }
    private func bulkControls(_ collection: GameCollection, library: Library, games: [Game], chosen: [Game]) -> some View {
        let others = gameCollectionsOf(library).filter { $0.id != collectionId }, target = model.target.isEmpty ? others.first?.id ?? collectionId : model.target
        return Section("\(chosen.count) selected") {
            Button(chosen.count == model.shown(games).count ? "Select none" : "Select all") { model.selected = chosen.count == model.shown(games).count ? [] : Set(model.shown(games).map(\.id)) }
            Picker("Move or copy to", selection: Binding(get: { target }, set: { model.target = $0 })) {
                ForEach(others, id: \.id) { Text($0.name).tag($0.id) }; Text(collection.name + " (this one)").tag(collectionId)
            }
            Button("Move") { Task { _ = await model.bulk(app, games: games, target: target, copy: false) } }.disabled(!app.store.online || chosen.isEmpty || target == collectionId)
            Button("Copy") { Task { _ = await model.bulk(app, games: games, target: target, copy: true) } }.disabled(!app.store.online || chosen.isEmpty)
            ShareLink(item: PGNExport(text: gamesAsFile(chosen), name: collection.name), preview: SharePreview(collection.name)) { Text("Export selected") }.disabled(chosen.isEmpty)
            Button("Delete selected", role: .destructive) { deletingGames = true }.disabled(!app.store.online || chosen.isEmpty)
        }
    }
    private func shift(_ game: Game, _ direction: GameShift, _ library: Library) {
        let placements = shiftGame(library, game, direction)
        Task { _ = await app.edit { try await $0.placeGames(placements) } }
    }
}
