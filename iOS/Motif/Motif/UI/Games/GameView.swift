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
private enum GamePanel: String, Identifiable { case comment, details; var id: String { rawValue } }
private struct GameContentView: View {
    let game: Game
    let app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var model: GameViewModel
    /// Follows the board's position; the bar that shows it comes later.
    @State private var analyzer: Analyzer
    @State private var panel: GamePanel?
    @State private var deleteMove = false
    @State private var deleteGame = false
    @State private var alternativesHidden = false
    @State private var alternativesOpen = false
    init(game: Game, app: AppState) {
        self.game = game; self.app = app
        _model = State(initialValue: GameViewModel(game, online: app.store.online) { changes in
            await app.edit { try await $0.updateGame(game.id, changes) }
        })
        _analyzer = State(initialValue: Analyzer.live())
    }
    var body: some View {
        Group {
            if let tree = model.tree {
                GeometryReader { geometry in
                    let width = min(geometry.size.width, geometry.size.height * 0.6)
                    VStack(spacing: 0) {
                        BoardView(fen: model.fen, orientation: model.orientation, interactive: model.online,
                                  highlight: model.node.map { (moveFrom($0.uci), moveTo($0.uci)) }, onMove: model.play)
                            .frame(width: width, height: width)
                        if let problem = model.problem { Text(problem).font(.caption).foregroundStyle(.red).padding(.top, 4) }
                        MoveListView(game: tree, path: model.path, go: model.go, scrolled: hideAlternatives) { moveMenu($0) }
                            .safeAreaInset(edge: .top, spacing: 0) { commentCard }
                            .overlay(alignment: .bottomTrailing) { alternatives(tree) }
                            .frame(maxHeight: .infinity)
                    }.frame(maxWidth: .infinity)
                }.navigationTitle(gameTitle(tree.headers)).navigationSubtitle(gameSubtitle(tree.headers)).navigationBarTitleDisplayMode(.inline)
            } else { unreadable }
        }.toolbar {
            ToolbarItem(placement: .topBarTrailing) { Menu { gameMenu } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Game actions").accessibilityIdentifier("game-actions") }
            if model.tree != nil {
                ToolbarItem(placement: .bottomBar) { control("Flip board", "arrow.up.arrow.down", disabled: !model.online, action: model.flip) }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItemGroup(placement: .bottomBar) {
                    control("Go to start", "backward.end.fill", disabled: model.path.isEmpty) { model.go([]) }
                    control("Previous move", "chevron.left", disabled: model.path.isEmpty, action: model.back)
                    control("Next move", "chevron.right", disabled: model.following.isEmpty, action: model.next)
                    control("Go to end", "forward.end.fill", disabled: model.following.isEmpty, action: model.end)
                }
            }
        }
            .sheet(item: $panel) { presented in
                switch presented {
                case .comment: CommentSheet(title: model.currentName, value: model.node?.comment ?? (model.path.isEmpty ? model.tree?.comment : nil), online: model.online, save: model.comment)
                case .details: if let tree = model.tree { GameDetailsSheet(headers: tree.headers, online: model.online, save: model.details).environment(app) }
                }
            }
            .confirmationDialog("Delete this move and every move after it?", isPresented: $deleteMove, titleVisibility: .visible) { Button("Delete from here", role: .destructive) { model.deleteHere() } }
            .confirmationDialog("Delete this game?", isPresented: $deleteGame, titleVisibility: .visible) {
                Button("Delete game", role: .destructive) { Task { if await app.edit({ try await $0.deleteGames([game.id]) }) { dismiss() } } }
            }
            .sensoryFeedback(.selection, trigger: model.path)
            .sensoryFeedback(.error, trigger: model.problem) { _, problem in problem != nil }
            .onChange(of: model.path) { alternativesHidden = false; alternativesOpen = false }
            .onChange(of: game) { _, next in model.receive(next) }
            .onChange(of: app.store.online) { _, online in model.online = online }
            .onChange(of: model.fen, initial: true) { _, fen in if model.tree != nil { analyzer.show(fen: fen) } }
            .onChange(of: phase) { _, phase in if phase == .active { analyzer.resume() } else { analyzer.pause() } }
            .onAppear { analyzer.resume() }
            .onDisappear { analyzer.pause() }
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
    /// The PGN didn't parse: say so, offer the two things that still work, and show the text as stored.
    private var unreadable: some View {
        ScrollView {
            VStack(spacing: 8) {
                EmptyState(title: "Can't Read This Game", systemImage: "exclamationmark.triangle",
                           description: "Its PGN has a mistake Motif can't get past. Copy it to fix it elsewhere, or delete the game.",
                           action: .init(title: "Copy PGN", identifier: "game-unreadable-copy") { UIPasteboard.general.string = game.pgn; app.showNotice("PGN copied.") },
                           secondary: .init(title: "Delete", identifier: "game-unreadable-delete", disabled: !model.online, role: .destructive) { deleteGame = true })
                Text(verbatim: game.pgn).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                    .padding(.horizontal)
                    .accessibilityLabel("PGN as stored").accessibilityValue(game.pgn)
                    .accessibilityIdentifier("game-unreadable-pgn")
            }.padding(.bottom)
        }
        .navigationTitle(gameTitle(readHeaders(game.pgn))).navigationBarTitleDisplayMode(.inline)
    }
    /// Only a position with a comment shows the card; the list scrolls beneath it.
    @ViewBuilder private var commentCard: some View {
        if !model.comment.isEmpty {
            Button { panel = .comment } label: {
                Text(model.comment).font(.subheadline).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 12)
            }.buttonStyle(.plain).disabled(!model.online)
                .glassEffect(.regular, in: .rect(cornerRadius: 14)).padding(.horizontal, 16).padding(.top, 8)
                .accessibilityIdentifier("game-comment")
        }
    }
    /// Alternatives to the current move, main line first; capped at three
    /// until opened, and the cap always keeps the current move in view.
    @ViewBuilder private func alternatives(_ tree: ParsedGame) -> some View {
        let parent = Array(model.path.dropLast())
        let siblings: [MoveNode] = model.path.isEmpty ? [] : parent.isEmpty ? tree.moves : nodeAt(tree, parent)?.children ?? []
        if siblings.count > 1, !alternativesHidden, let current = model.path.last {
            let number = moveNumber(fenAt(tree, parent), true) ?? "", cap = 3
            let shown: [Int] = alternativesOpen || siblings.count <= cap ? Array(siblings.indices) : current < cap ? Array(0..<cap) : Array(0..<cap - 1) + [current]
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(shown, id: \.self) { index in
                    let selected = index == current
                    Button { model.go(parent + [index]) } label: {
                        HStack(spacing: 6) { if selected { Image(systemName: "checkmark").font(.caption.bold()).accessibilityHidden(true) }; Text(number + " " + siblings[index].san) }
                            .font(.subheadline.weight(selected ? .semibold : .regular)).foregroundStyle(selected ? Color.white : Color.primary)
                            .padding(.horizontal, 14).frame(minHeight: 36)
                    }.buttonStyle(.plain)
                        .glassEffect(selected ? .regular.tint(.motifAccentStrong).interactive() : .regular.interactive(), in: .capsule)
                        .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("alternative-\(index)")
                }
                if siblings.count > cap {
                    Button { withAnimation(.snappy) { alternativesOpen.toggle() } } label: {
                        HStack(spacing: 4) { Text(alternativesOpen ? "Show less" : "+\(siblings.count - cap) more"); Image(systemName: alternativesOpen ? "chevron.down" : "chevron.up").accessibilityHidden(true) }
                            .font(.footnote.weight(.semibold)).foregroundStyle(Color.motifAccentStrong).padding(.horizontal, 12).frame(minHeight: 32)
                    }.buttonStyle(.plain).glassEffect(.regular.interactive(), in: .capsule).accessibilityIdentifier("alternatives-toggle")
                }
            }.padding(.trailing, 16).padding(.bottom, 8).transition(.opacity)
                .accessibilityElement(children: .contain).accessibilityLabel("Alternatives to this move")
        }
    }
    private func hideAlternatives() { withAnimation(.easeOut(duration: 0.2)) { alternativesHidden = true; alternativesOpen = false } }
    private func control(_ label: String, _ image: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(label, systemImage: image).font(.title3).imageScale(.large).frame(minWidth: 40, minHeight: 40) }.disabled(disabled).accessibilityIdentifier("game-" + label.lowercased().replacingOccurrences(of: " ", with: "-"))
    }
    @ViewBuilder private var gameMenu: some View {
        if let tree = model.tree {
            Button("Edit Details", systemImage: "pencil") { panel = .details }
            Button(commentAction(model.path.isEmpty, model.comment.isEmpty), systemImage: "text.bubble") { panel = .comment }.disabled(!model.online).accessibilityIdentifier("game-edit-comment")
            Section {
                Button("Copy PGN", systemImage: "doc.on.doc") { UIPasteboard.general.string = writePgn(tree); app.showNotice("PGN copied.") }.accessibilityIdentifier("game-copy-pgn")
                ShareLink(item: PGNExport(text: writePgn(tree), name: gameTitle(tree.headers)), preview: SharePreview(gameTitle(tree.headers))) { Label("Export PGN…", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("game-export-pgn")
            }
        }
        Section { Button("Delete Game", systemImage: "trash", role: .destructive) { deleteGame = true }.disabled(!model.online) }
    }
    /// Acting on a move from its context menu selects it first.
    @ViewBuilder private func moveMenu(_ cell: Cell) -> some View {
        let empty = displayComment(cell.node.comment).isEmpty && displayComment(cell.node.before).isEmpty
        Button(commentAction(false, empty), systemImage: "text.bubble") { model.go(cell.path); panel = .comment }.disabled(!model.online)
        if !onMainLine(cell.path) { Button("Make Main Line", systemImage: "arrow.up.to.line") { model.go(cell.path); model.promote() }.disabled(!model.online) }
        Section {
            Button(role: .destructive) { model.go(cell.path); deleteMove = true } label: { Label("Delete From Here", systemImage: "trash"); Text(countLabel(movesFrom(cell.node), "move")) }.disabled(!model.online)
        }
    }
    private func commentAction(_ game: Bool, _ empty: Bool) -> String { (empty ? "Add " : "Edit ") + (game ? "Game Note" : "Comment") }
}
