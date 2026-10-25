import SwiftUI

struct GameView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let gameId: String
    var body: some View {
        Group {
            if let game = app.store.library?.games.first(where: { $0.id == gameId }) { GameContentView(game: game, app: app) }
            else { Color.clear.onAppear { dismiss() } }
        }.toolbar(.hidden, for: .tabBar)
    }
}
private enum GamePanel: String, Identifiable { case comment, details, actions, move; var id: String { rawValue } }
private struct GameContentView: View {
    let game: Game
    let app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var model: GameViewModel
    @State private var panel: GamePanel?
    @State private var deleteMove = false
    @State private var deleteGame = false
    init(game: Game, app: AppState) {
        self.game = game; self.app = app
        _model = State(initialValue: GameViewModel(game, online: app.store.online) { changes in
            await app.edit { try await $0.updateGame(game.id, changes) }
        })
    }
    var body: some View {
        Group {
            if let tree = model.tree {
                GeometryReader { geometry in
                    let width = min(geometry.size.width - 24, geometry.size.height * 0.57)
                    VStack(spacing: 6) {
                        let subtitle = gameSubtitle(tree.headers)
                        if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        BoardView(fen: model.fen, orientation: model.orientation, interactive: model.online,
                                  highlight: model.node.map { (moveFrom($0.uci), moveTo($0.uci)) }, onMove: model.play)
                            .frame(width: width, height: width)
                        if let problem = model.problem { Text(problem).font(.caption).foregroundStyle(.red) }
                        nextMoves
                        commentStrip
                        MoveListView(game: tree, path: model.path, go: model.go, hold: { model.go($0); panel = .move })
                            .frame(maxHeight: .infinity)
                        controls
                    }.frame(maxWidth: .infinity).padding(.bottom, 6)
                }.navigationTitle(gameTitle(tree.headers)).navigationBarTitleDisplayMode(.inline)
            } else {
                ScrollView { VStack { Text("This game's PGN can't be read.").foregroundStyle(.red); Text(game.pgn).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }.padding() }
            }
        }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button { panel = .actions } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Game actions").accessibilityIdentifier("game-actions") } }
            .sheet(item: $panel) { presented in
                switch presented {
                case .comment: CommentSheet(title: model.currentName, value: model.node?.comment ?? (model.path.isEmpty ? model.tree?.comment : nil), online: model.online, save: model.comment)
                case .details: if let tree = model.tree { GameDetailsSheet(headers: tree.headers, online: model.online, save: model.details).environment(app) }
                case .actions, .move: actions(presented)
                }
            }
            .confirmationDialog("Delete this move and every move after it?", isPresented: $deleteMove, titleVisibility: .visible) { Button("Delete from here", role: .destructive) { model.deleteHere(); panel = nil } }
            .confirmationDialog("Delete this game?", isPresented: $deleteGame, titleVisibility: .visible) {
                Button("Delete game", role: .destructive) { Task { if await app.edit({ try await $0.deleteGames([game.id]) }) { panel = nil; dismiss() } } }
            }
            .onChange(of: game) { _, next in model.receive(next) }
            .onChange(of: app.store.online) { _, online in model.online = online }
            .focusable().focusEffectDisabled()
            .onKeyPress(.leftArrow) { model.back(); return .handled }
            .onKeyPress(.rightArrow) { model.next(); return .handled }
            .task {
                #if DEBUG
                if app.launchRoute == "game-details" { panel = .details }
                if app.launchRoute == "game-comment" { model.next(); panel = .comment }
                if app.launchRoute == "game-variation" { model.go([0, 0, 1]) }
                #endif
            }
    }
    private var nextMoves: some View {
        HStack(spacing: 8) {
            Text("Next").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(model.following.enumerated()), id: \.offset) { index, node in
                        Button((moveNumber(model.fen, true) ?? "") + " " + node.san) { model.go(model.path + [index]) }.font(.subheadline).buttonStyle(.bordered)
                    }
                    if model.following.isEmpty { Text("End of the line").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.padding(.horizontal, 12).frame(height: 36)
    }
    private var commentStrip: some View {
        Button { panel = .comment } label: {
            Text(model.comment.isEmpty ? (model.path.isEmpty ? "Add a note on the game" : "Add a comment") : model.comment)
                .font(.footnote).foregroundStyle(model.comment.isEmpty ? .secondary : .primary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 6)
        }.buttonStyle(.plain).disabled(!model.online).accessibilityIdentifier("game-comment")
    }
    private var controls: some View {
        HStack(spacing: 0) {
            control("Flip board", "arrow.up.arrow.down", disabled: !model.online, action: model.flip)
            control("Go to start", "backward.end", disabled: model.path.isEmpty) { model.go([]) }
            control("Previous move", "chevron.left", disabled: model.path.isEmpty, action: model.back)
            control("Next move", "chevron.right", disabled: model.following.isEmpty, action: model.next)
            control("Go to end", "forward.end", disabled: model.following.isEmpty, action: model.end)
            control("Comment", "text.bubble", disabled: !model.online, id: "game-comment-control") { panel = .comment }
        }.padding(.horizontal, 8).background(.bar)
    }
    private func control(_ label: String, _ image: String, disabled: Bool, id: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).frame(maxWidth: .infinity).frame(height: 44) }.disabled(disabled).accessibilityLabel(label).accessibilityIdentifier(id ?? "game-" + label.lowercased().replacingOccurrences(of: " ", with: "-"))
    }
    private func actions(_ kind: GamePanel) -> some View {
        NavigationStack {
            List {
                if kind == .actions, let tree = model.tree {
                    Button("Edit details") { panel = .details }
                    Button("Copy PGN") { UIPasteboard.general.string = writePgn(tree); app.notice = "PGN copied."; panel = nil }.accessibilityIdentifier("game-copy-pgn")
                    ShareLink(item: PGNExport(text: writePgn(tree), name: gameTitle(tree.headers)), preview: SharePreview(gameTitle(tree.headers))) { Label("Export PGN", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("game-export-pgn")
                }
                if let node = model.node {
                    Section(model.currentName) {
                        Button("Edit comment") { panel = .comment }.disabled(!model.online)
                        if !onMainLine(model.path) { Button("Make main line") { model.promote(); panel = nil }.disabled(!model.online) }
                        Button(role: .destructive) { deleteMove = true } label: {
                            HStack { Text("Delete from here"); Spacer(); Text(countLabel(movesFrom(node), "move")).foregroundStyle(.secondary) }
                        }.disabled(!model.online)
                    }
                }
                if kind == .actions { Button("Delete game", role: .destructive) { deleteGame = true }.disabled(!model.online) }
                OfflineNote()
            }.navigationTitle(kind == .actions ? "Game actions" : "Move actions").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { panel = nil } } }
        }.environment(app).presentationDetents([.medium, .large])
    }
}
