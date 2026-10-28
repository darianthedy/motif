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
/// A game that isn't in the library, such as a puzzle opened for analysis: its
/// edits stay on the device unless it is saved as a new game.
struct ScratchAnalysis { var title: String; var subtitle: String }
private enum GamePanel: String, Identifiable { case comment, details, saveAsGame; var id: String { rawValue } }
struct GameContentView: View {
    let game: Game
    let app: AppState
    var scratch: ScratchAnalysis?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var model: GameViewModel
    /// Follows the board's position for the evaluation bar.
    @State private var analyzer: Analyzer
    @AppStorage("evalBarShown") private var evalBarShown = true
    @AppStorage("engineLinesShown") private var linesShown = false
    @State private var panel: GamePanel?
    @State private var deleteMove = false
    @State private var deleteGame = false
    @State private var leaving = false
    @State private var alternativesHidden = false
    @State private var alternativesOpen = false
    init(game: Game, app: AppState, scratch: ScratchAnalysis? = nil) {
        self.game = game; self.app = app; self.scratch = scratch
        _model = State(initialValue: GameViewModel(game, online: app.store.online) { changes in
            guard scratch == nil else { return false }
            return await app.edit { try await $0.updateGame(game.id, changes) }
        })
        _analyzer = State(initialValue: Analyzer.live(route: app.launchRoute))
    }
    var body: some View {
        screen
            .sensoryFeedback(.selection, trigger: model.path)
            .sensoryFeedback(.error, trigger: model.problem) { _, problem in problem != nil }
            .onChange(of: model.path) { alternativesHidden = false; alternativesOpen = false }
            .onChange(of: game) { _, next in model.receive(next) }
            .onChange(of: app.store.online) { _, online in model.online = online }
            .onChange(of: evalBarShown || linesShown, initial: true) { _, needed in analyzer.enabled = needed }
            .onChange(of: linesShown, initial: true) { _, shown in analyzer.lineCount = shown ? EngineLinesView.count : 1 }
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
    /// Split from `body` so each half type-checks in reasonable time.
    private var screen: some View {
        content
            .navigationBarBackButtonHidden(guardsLeaving).toolbar { toolbar }
            .safeAreaBar(edge: .bottom) { if model.tree != nil { controls } }
            .sheet(item: $panel) { presented in
                switch presented {
                case .comment: CommentSheet(title: model.currentName, value: model.node?.comment ?? (model.path.isEmpty ? model.tree?.comment : nil), online: true, save: model.comment)
                case .details: if let tree = model.tree { GameDetailsSheet(headers: tree.headers, save: model.details).environment(app) }
                case .saveAsGame: if let tree = model.tree { SaveAsGameSheet(content: GameContent(pgn: writePgn(tree), orientation: model.orientation)).environment(app) }
                }
            }
            .confirmationDialog("Delete this move and every move after it?", isPresented: $deleteMove, titleVisibility: .visible) { Button("Delete from here", role: .destructive) { model.deleteHere() } }
            .confirmationDialog("Delete this game?", isPresented: $deleteGame, titleVisibility: .visible) {
                Button("Delete game", role: .destructive) { Task { if await app.edit({ try await $0.deleteGames([game.id]) }) { dismiss() } } }
            }
            .alert(model.online ? "Save changes to this game?" : "Discard unsaved changes?", isPresented: $leaving) { leaveActions } message: { leaveMessage }
    }
    @ViewBuilder private var content: some View {
        if let tree = model.tree {
            GeometryReader { geometry in
                // The bar takes its width from the board, so the move list and toolbars keep their layout.
                let width = min(geometry.size.width - 2 * Self.margin - (evalBarShown ? EvalBar.width + EvalBar.gap : 0), geometry.size.height * 0.6)
                VStack(spacing: 0) {
                    HStack(spacing: EvalBar.gap) {
                        if evalBarShown { EvalBar(evaluation: analyzer.evaluation, orientation: model.orientation).frame(height: width) }
                        BoardView(fen: model.fen, orientation: model.orientation, interactive: true,
                                  highlight: model.node.map { (moveFrom($0.uci), moveTo($0.uci)) }, onMove: model.play)
                            .frame(width: width, height: width)
                    }.padding(.top, 8)
                    if linesShown {
                        EngineLinesView(lines: analyzer.lines, fen: model.fen, play: model.play)
                            .padding(.horizontal, Self.margin).padding(.top, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if let problem = model.problem { Text(problem).font(.caption).foregroundStyle(.red).padding(.top, 4) }
                    MoveListView(game: tree, path: model.path, go: model.go, scrolled: hideAlternatives) { moveMenu($0) }
                        .safeAreaInset(edge: .top, spacing: 0) { commentCard }
                        .overlay(alignment: .bottomTrailing) { alternatives(tree) }
                        .frame(maxHeight: .infinity)
                }.frame(maxWidth: .infinity)
            }.navigationTitle(scratch?.title ?? gameTitle(tree.headers)).navigationSubtitle(scratch?.subtitle ?? gameSubtitle(tree.headers)).navigationBarTitleDisplayMode(.inline)
        } else { unreadable }
    }
    /// A stored game asks before its edits are left behind; a scratch one has nothing to save to.
    private var guardsLeaving: Bool { model.unsaved && scratch == nil }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if guardsLeaving {
            ToolbarItem(placement: .topBarLeading) { Button("Back", systemImage: "chevron.backward") { leaving = true }.accessibilityIdentifier("game-back") }
        }
        ToolbarItem(placement: .topBarTrailing) { Menu { gameMenu } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Game actions").accessibilityIdentifier("game-actions") }
    }
    /// Side margin for the board and the engine lines.
    private static let margin: CGFloat = 16
    /// Flip and engine lines, then large previous and next buttons; holding those
    /// jumps to the start or the end.
    private var controls: some View {
        HStack(spacing: 4) {
            Button(action: model.flip) { Image(systemName: "arrow.up.arrow.down").font(.title3).frame(width: 44, height: 44).contentShape(.rect) }
                .buttonStyle(.plain).accessibilityLabel("Flip board").accessibilityIdentifier("game-flip-board")
            Button { withAnimation(.snappy) { linesShown.toggle() } } label: {
                Image(systemName: "list.bullet.indent").font(.title3).foregroundStyle(linesShown ? Color.white : Color.primary)
                    .frame(width: 44, height: 44).background(linesShown ? Color.motifAccentStrong : Color.clear, in: .circle).contentShape(.circle)
            }.buttonStyle(.plain).accessibilityLabel("Engine lines").accessibilityAddTraits(linesShown ? .isSelected : [])
                .accessibilityIdentifier("game-engine-lines")
            Divider().frame(height: 28).padding(.horizontal, 4)
            stepper("Previous move", "chevron.left", hold: "Go to start", disabled: model.path.isEmpty, step: model.back) { model.go([]) }
            stepper("Next move", "chevron.right", hold: "Go to end", disabled: model.following.isEmpty, step: model.next, jump: model.end)
        }
        .padding(.horizontal, 6).frame(height: 56)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, Self.margin).padding(.bottom, 8)
    }
    /// A tap steps one move; a long press jumps all the way. Gestures rather than a
    /// `Button`, so the long press doesn't also count as a tap.
    private func stepper(_ label: String, _ image: String, hold: String, disabled: Bool, step: @escaping () -> Void, jump: @escaping () -> Void) -> some View {
        Image(systemName: image).font(.title2.weight(.semibold))
            .foregroundStyle(disabled ? Color(.tertiaryLabel) : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(.tertiarySystemFill), in: .capsule).contentShape(.capsule)
            .onTapGesture { if !disabled { step() } }
            .onLongPressGesture(minimumDuration: 0.4) { if !disabled { jump() } }
            .disabled(disabled)
            .accessibilityElement().accessibilityLabel(label).accessibilityAddTraits(.isButton)
            .accessibilityAction { if !disabled { step() } }
            .accessibilityAction(named: hold) { if !disabled { jump() } }
            .accessibilityIdentifier("game-" + label.lowercased().replacingOccurrences(of: " ", with: "-"))
    }
    @ViewBuilder private var leaveActions: some View {
        if model.online { Button("Save") { Task { if await model.save() { dismiss() } } } }
        Button("Discard Changes", role: .destructive) { model.discard(); dismiss() }
        Button("Cancel", role: .cancel) {}
    }
    @ViewBuilder private var leaveMessage: some View { if !model.online { Text("You're offline, so they can't be saved.") } }
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
            }.buttonStyle(.plain)
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
    @ViewBuilder private var gameMenu: some View {
        if let tree = model.tree {
            if scratch == nil {
                Button("Save", systemImage: "square.and.arrow.down") { Task { if await model.save() { app.showNotice("Game saved.") } } }
                    .disabled(!model.canSave).accessibilityIdentifier("game-save")
                Button("Edit Details", systemImage: "pencil") { panel = .details }
                Button(commentAction(model.path.isEmpty, model.comment.isEmpty), systemImage: "text.bubble") { panel = .comment }.accessibilityIdentifier("game-edit-comment")
            }
            Button(evalBarShown ? "Hide Evaluation" : "Show Evaluation", systemImage: evalBarShown ? "eye.slash" : "chart.bar.yaxis") { evalBarShown.toggle() }
                .accessibilityIdentifier("game-toggle-evaluation")
            Section {
                if scratch != nil {
                    Button("Save as Game…", systemImage: "square.and.arrow.down") { panel = .saveAsGame }
                        .disabled(!model.online).accessibilityIdentifier("game-save-as-game")
                }
                Button("Copy PGN", systemImage: "doc.on.doc") { UIPasteboard.general.string = writePgn(tree); app.showNotice("PGN copied.") }.accessibilityIdentifier("game-copy-pgn")
                ShareLink(item: PGNExport(text: writePgn(tree), name: gameTitle(tree.headers)), preview: SharePreview(gameTitle(tree.headers))) { Label("Export PGN…", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("game-export-pgn")
            }
        }
        if scratch == nil { Section { Button("Delete Game", systemImage: "trash", role: .destructive) { deleteGame = true }.disabled(!model.online) } }
    }
    /// Acting on a move from its context menu selects it first.
    @ViewBuilder private func moveMenu(_ cell: Cell) -> some View {
        let empty = displayComment(cell.node.comment).isEmpty && displayComment(cell.node.before).isEmpty
        Button(commentAction(false, empty), systemImage: "text.bubble") { model.go(cell.path); panel = .comment }
        if !onMainLine(cell.path) { Button("Make Main Line", systemImage: "arrow.up.to.line") { model.go(cell.path); model.promote() } }
        Section {
            Button(role: .destructive) { model.go(cell.path); deleteMove = true } label: { Label("Delete From Here", systemImage: "trash"); Text(countLabel(movesFrom(cell.node), "move")) }
        }
    }
    private func commentAction(_ game: Bool, _ empty: Bool) -> String { (empty ? "Add " : "Edit ") + (game ? "Game Note" : "Comment") }
}
