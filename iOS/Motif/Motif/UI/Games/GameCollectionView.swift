import SwiftUI

@Observable @MainActor final class GameCollectionModel {
    var query = ""
    var selected: Set<String> = []
    /// The order just dragged in, shown until the library catches up with the write.
    private(set) var pendingOrder: [String]?
    func shown(_ games: [Game]) -> [Game] {
        var games = games
        if let pendingOrder {
            let rank = Dictionary(uniqueKeysWithValues: pendingOrder.enumerated().map { ($1, $0) })
            games.sort { rank[$0.id] ?? .max < rank[$1.id] ?? .max }
        }
        return games.filter { matchesSearch(readHeaders($0.pgn), query) }
    }
    func allSelected(_ shown: [Game]) -> Bool { !shown.isEmpty && Set(shown.map(\.id)).isSubset(of: selected) }
    func toggleAll(_ shown: [Game]) {
        let ids = Set(shown.map(\.id))
        selected = allSelected(shown) ? selected.subtracting(ids) : selected.union(ids)
    }
    /// Renumbers the dragged order from 0, sending only the games whose position changed.
    func placements(_ games: [Game], from: IndexSet, to: Int) -> [GamePlacement] {
        var ordered = games; ordered.move(fromOffsets: from, toOffset: to)
        return ordered.enumerated().compactMap { n, game in
            game.position == n ? nil : GamePlacement(id: game.id, collectionId: game.collectionId, position: n)
        }
    }
    /// `games` is the whole collection in display order; a filtered list can't be reordered.
    func reorder(_ app: AppState, games: [Game], from: IndexSet, to: Int) async -> Bool {
        guard app.store.online, pendingOrder == nil, query.isEmpty else { return false }
        let changed = placements(games, from: from, to: to)
        guard !changed.isEmpty else { return false }
        var ordered = games; ordered.move(fromOffsets: from, toOffset: to)
        pendingOrder = ordered.map(\.id)
        let saved = await app.edit { try await $0.placeGames(changed) }
        pendingOrder = nil; return saved
    }
    func bulk(_ app: AppState, games: [Game], target: String, copy: Bool) async -> Bool {
        guard app.store.online, let library = app.store.library else { return false }
        let chosen = games.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return false }
        if copy {
            let added = copyGames(library, chosen, target)
            return await app.edit({ try await $0.addGames(added) }, done: "Copied \(countLabel(added.count, "game")).")
        }
        let placements = moveGames(library, chosen, target)
        return await app.edit({ try await $0.placeGames(placements) }, done: "Moved \(countLabel(placements.count, "game")).")
    }
}
enum GameTransfer: String, Identifiable { case move, copy; var id: String { rawValue } }
struct GameCollectionView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let collectionId: String
    @State private var model = GameCollectionModel()
    @State private var editMode = EditMode.inactive
    @State private var adding = false
    @State private var renaming = false
    @State private var name = ""
    @State private var deletingCollection = false
    @State private var deletingGames = false
    @State private var transfer: GameTransfer?
    private var editing: Bool { editMode.isEditing }
    var body: some View {
        @Bindable var model = model
        Group {
            if let library = app.store.library, let collection = library.gameCollections.first(where: { $0.id == collectionId }) {
                collectionContent(collection, games: gamesIn(library, collectionId))
            } else { Color.clear.onAppear { dismiss() } }
        }
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Players, event, opening")
            .environment(\.editMode, $editMode)
            .navigationBarBackButtonHidden(editing)
            .toolbar(editing ? .hidden : .visible, for: .tabBar)
            .onChange(of: editing) { if !editing { model.selected = [] } }
            .sheet(isPresented: $adding) { AddGamesView(collectionId: collectionId).environment(app) }
            .sheet(item: $transfer) { transfer in
                GameDestinationSheet(model: model, collectionId: collectionId, transfer: transfer) { withAnimation { editMode = .inactive } }.environment(app)
            }
            .alert("Rename the collection", isPresented: $renaming) {
                TextField("Name", text: $name)
                Button("Save") {
                    let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chosen.isEmpty { Task { _ = await app.edit { try await $0.renameGameCollection(collectionId, chosen) } } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this collection and its games?", isPresented: $deletingCollection, titleVisibility: .visible) {
                Button("Delete Collection", role: .destructive) { Task { if await app.edit({ try await $0.deleteGameCollection(collectionId) }) { app.gamesPath = [] } } }
            }
            .confirmationDialog("Delete the selected games?", isPresented: $deletingGames, titleVisibility: .visible) {
                Button("Delete \(countLabel(model.selected.count, "Game"))", role: .destructive) {
                    let ids = Array(model.selected)
                    Task { if await app.edit({ try await $0.deleteGames(ids) }, done: "Deleted \(countLabel(ids.count, "game")).") { withAnimation { editMode = .inactive } } }
                }
            }
            .task {
                #if DEBUG
                if app.launchRoute == "game-add" { adding = true }
                #endif
            }
    }
    private func collectionContent(_ collection: GameCollection, games: [Game]) -> some View {
        let shown = model.shown(games), chosen = games.filter { model.selected.contains($0.id) }
        let reorder: ((IndexSet, Int) -> Void)? = editing && app.store.online && model.query.isEmpty && model.pendingOrder == nil
            ? { from, to in Task { _ = await model.reorder(app, games: shown, from: from, to: to) } } : nil
        return ZStack {
            if games.isEmpty {
                EmptyState(title: "No Games", systemImage: "checkerboard.rectangle",
                           description: "Import games as PGN or play one in on the board.",
                           action: .init(title: "Import PGN", identifier: "add-games-empty", disabled: !app.store.online) { adding = true },
                           secondary: .init(title: "New Game on Board", disabled: !app.store.online) { adding = true })
            } else {
                List(selection: Bindable(model).selected) {
                    ForEach(shown, id: \.id) { game in
                        Group {
                            if editing { GameRow(game: game) }
                            else { NavigationLink(value: GamesRoute.game(collectionId, game.id)) { GameRow(game: game) } }
                        }.accessibilityIdentifier("game-row-" + game.id)
                    }
                    .onMove(perform: reorder)
                }
                .overlay { if shown.isEmpty { ContentUnavailableView.search(text: model.query) } }
            }
        }
        .navigationTitle(editing ? (chosen.isEmpty ? "Select Games" : "\(chosen.count) Selected") : collection.name)
        .navigationSubtitle(editing ? "" : countLabel(games.count, "game"))
        .navigationBarTitleDisplayMode(editing ? .inline : .large)
        .toolbar {
            if editing {
                ToolbarItem(placement: .topBarLeading) {
                    Button(model.allSelected(shown) ? "Deselect All" : "Select All") { model.toggleAll(shown) }
                        .disabled(shown.isEmpty).accessibilityIdentifier("game-select-all")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", systemImage: "checkmark") { withAnimation { editMode = .inactive } }
                        .buttonStyle(.glassProminent).accessibilityIdentifier("game-select-done")
                }
                bulkBar(collection, chosen: chosen)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Add Games", systemImage: "plus") {
                        Button("Import PGN…", systemImage: "doc.text") { adding = true }
                        Button("New Game on Board…", systemImage: "checkerboard.rectangle") { adding = true }
                    }.disabled(!app.store.online).accessibilityIdentifier("add-games")
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Select Games", systemImage: "checkmark.circle") { withAnimation { editMode = .active } }
                            .disabled(games.isEmpty).accessibilityIdentifier("game-select")
                        ShareLink(item: PGNExport(text: gamesAsFile(games), name: collection.name), preview: SharePreview(collection.name)) {
                            Label("Export as PGN", systemImage: "square.and.arrow.up")
                        }.disabled(games.isEmpty)
                        Button("Rename…", systemImage: "pencil") { name = collection.name; renaming = true }.disabled(!app.store.online)
                        Divider()
                        Button("Delete Collection", systemImage: "trash", role: .destructive) { deletingCollection = true }.disabled(!app.store.online)
                    }.accessibilityIdentifier("game-collection-actions")
                }
            }
        }
    }
    @ToolbarContentBuilder private func bulkBar(_ collection: GameCollection, chosen: [Game]) -> some ToolbarContent {
        let none = chosen.isEmpty, offline = !app.store.online
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Move", systemImage: "folder") { transfer = .move }.disabled(none || offline).accessibilityIdentifier("game-bulk-move")
            Button("Copy", systemImage: "plus.square.on.square") { transfer = .copy }.disabled(none || offline).accessibilityIdentifier("game-bulk-copy")
            ShareLink(item: PGNExport(text: gamesAsFile(chosen), name: collection.name), preview: SharePreview(collection.name)) {
                Label("Export", systemImage: "square.and.arrow.up")
            }.disabled(none).accessibilityIdentifier("game-bulk-export")
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button("Delete", systemImage: "trash", role: .destructive) { deletingGames = true }
                .tint(.red).disabled(none || offline).accessibilityIdentifier("game-bulk-delete")
        }
    }
}
/// Title, "event · round · date · opening", and the result as a chip.
private struct GameRow: View {
    let game: Game
    var body: some View {
        let headers = readHeaders(game.pgn), details = gameDetails(headers)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(gameTitle(headers)).font(.body.weight(.medium)).lineLimit(2)
                if !details.isEmpty { Text(details).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if let result = ResultChip(headers["Result"]) { result }
        }
        .padding(.vertical, 2)
    }
}
private struct ResultChip: View {
    let text: String
    let spoken: String
    init?(_ result: String?) {
        switch result?.trimmingCharacters(in: .whitespaces) {
        case "1-0": text = "1–0"; spoken = "White won"
        case "0-1": text = "0–1"; spoken = "Black won"
        case "1/2-1/2": text = "½–½"; spoken = "Draw"
        default: return nil
        }
    }
    var body: some View {
        Text(text).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3).background(.fill.tertiary, in: .capsule)
            .accessibilityLabel(spoken)
    }
}
/// PGN's unknown values (?, ????.??.??, -) are left out; the event only shows when players gave the title.
private func gameDetails(_ headers: PgnHeaders) -> String {
    func known(_ name: String) -> String? {
        guard let value = headers[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.contains(where: { !"?.-".contains($0) }) else { return nil }
        return value
    }
    let players = known("White") != nil || known("Black") != nil
    let date = (headers["Date"] ?? "").components(separatedBy: ".").prefix { !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    return [players ? known("Event") : nil, known("Round").map { "Round " + $0 },
            date.isEmpty ? nil : date.joined(separator: "."), known("Opening") ?? known("ECO")]
        .compactMap { $0 }.joined(separator: " · ")
}
/// Move or copy the selection: pick another collection, then ✓.
private struct GameDestinationSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let model: GameCollectionModel
    let collectionId: String
    let transfer: GameTransfer
    let finished: () -> Void
    @State private var target: String?
    @State private var busy = false
    var body: some View {
        let library = app.store.library, games = library.map { gamesIn($0, collectionId) } ?? []
        let count = games.filter { model.selected.contains($0.id) }.count
        let title = "\(transfer == .copy ? "Copy" : "Move") \(countLabel(count, "Game"))"
        NavigationStack {
            List {
                Section {
                    ForEach(library.map(gameCollectionsOf) ?? [], id: \.id) { collection in
                        let current = collection.id == collectionId
                        Button { target = collection.id } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "checkerboard.rectangle").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                                    .frame(width: 30, height: 30).background(Color.motifAccentStrong.opacity(current ? 0.4 : 1), in: .rect(cornerRadius: 7))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(collection.name).foregroundStyle(current ? Color.secondary : Color.primary)
                                    Text(current ? "Current collection" : countLabel(library.map { gamesIn($0, collection.id).count } ?? 0, "game"))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if target == collection.id { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint) }
                            }
                        }
                        .disabled(current)
                        .accessibilityAddTraits(target == collection.id ? .isSelected : [])
                        .accessibilityIdentifier("game-destination-" + collection.id)
                    }
                } header: { Text(transfer == .copy ? "Copy To" : "Move To") }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .sheetToolbar(confirm: title, disabled: target == nil || busy || count == 0 || !app.store.online, identifier: "game-destination-confirm",
                          onCancel: { dismiss() }) {
                guard let target else { return }
                busy = true
                Task {
                    if await model.bulk(app, games: games, target: target, copy: transfer == .copy) { finished(); dismiss() }
                    busy = false
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
