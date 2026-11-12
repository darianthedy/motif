import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var model: GameViewModel
    /// Follows the board's position for the evaluation bar.
    @State private var analyzer: Analyzer
    @AppStorage("evalBarShown") private var evalBarShown = true
    @AppStorage("engineLinesShown") private var linesShown = false
    @State private var panel: GamePanel?
    @State private var deleteMove = false
    @State private var deleteGame = false
    @State private var leaving = false
    @State private var alternativesOpen = false
    /// A promotion waiting for its piece, answered by the row in the layout (decision 17).
    @State private var promotion: BoardPending?
    /// The content's size inside the safe area and the bars, for `BoardLayout`.
    @State private var container: CGSize = .zero
    /// The fold's active division in the same coordinates, nil when flat (D07).
    @State private var division: CGRect?
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
            // Diagnostics build only: when a menu action lands, against the menu's "shown" line.
            .diagChange("game", of: panel?.rawValue ?? "none") { "panel \($0)" }
            .diagChange("game", of: deleteGame) { "delete game dialog \($0)" }
            .diagChange("game", of: evalBarShown) { "evaluation shown \($0)" }
            .diagChange("game", of: linesShown) { "engine lines shown \($0)" }
            .sensoryFeedback(.error, trigger: model.problem) { _, problem in problem != nil }
            .onChange(of: model.path) { alternativesOpen = false }
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
                if CaptureFixture.current.has("problem") { model.problem = "That move isn't legal in this position." }
                #endif
            }
    }
    /// Split from `body` so each half type-checks in reasonable time.
    private var screen: some View {
        content
            .navigationBarBackButtonHidden(guardsLeaving).toolbar { toolbar }.background(TouchClockInstaller())
            // The game menu (F16); its items set flags the sheet and dialogs below read (F15).
            .motifOverflowMenu("Game actions", identifier: "game-actions") { gameMenu }
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
            // One view tree in every pose: the layout rule picks two panes or a stack, and
            // `AnyLayout` switches between them so the board, the list and the sheets keep their state.
            // On a fold the board takes the leading page or the top half, never crossing it (D07).
            let layout = BoardLayout(container: container, compact: sizeClass == .compact, evalBar: evalBarShown, division: division)
            let stack = layout.sideBySide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: layout.spacing))
                : AnyLayout(VStackLayout(alignment: .center, spacing: layout.spacing))
            // VoiceOver reads the board, then the column, then the bar items, whichever
            // side or page each lands on (§6.14, D10).
            stack {
                boardPane(layout).accessibilitySortPriority(2)
                column(tree, layout).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).accessibilitySortPriority(1)
            }
            .accessibilityElement(children: .contain)
            .padding(layout.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .motifOfferedSize($container)
            .motifDivision($division)
            .navigationTitle(scratch?.title ?? gameTitle(tree.headers)).navigationSubtitle(scratch?.subtitle ?? gameSubtitle(tree.headers)).navigationBarTitleDisplayMode(.inline)
        } else { unreadable }
    }
    private var promoting: (from: String, to: String)? {
        if case .promotion(let from, let to) = promotion { return (from, to) }
        return nil
    }
    /// The board with the evaluation bar on its leading side.
    private func boardPane(_ layout: BoardLayout) -> some View {
        HStack(spacing: layout.evalGap) {
            if evalBarShown { EvalBar(evaluation: analyzer.evaluation, orientation: model.orientation).frame(height: layout.board) }
            BoardView(fen: model.fen, orientation: model.orientation, interactive: true,
                      highlight: model.node.map { (moveFrom($0.uci), moveTo($0.uci)) }, onMove: model.play, pending: $promotion)
                .frame(width: layout.board, height: layout.board)
                .diagProbe("game.board") { "game \(game.id) path \(model.path) unsaved \(model.unsaved) mode \(layout.mode)" }
        }
    }
    /// Under the board or beside it, in the canvas's order. A short column (O, SV, IP)
    /// shows the engine lines instead of the moves, the alternatives as one row and the
    /// comment as one line (F7, F8).
    /// VoiceOver: a pending promotion first, then the problem, the moves (or the lines that
    /// replace them), and the alternatives and comment after them (§6.14).
    private func column(_ tree: ParsedGame, _ layout: BoardLayout) -> some View {
        VStack(spacing: layout.compact ? 8 : 10) {
            if let problem = model.problem {
                Text(problem).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).accessibilitySortPriority(3)
            }
            if let promoting {
                PieceRow(color: Board.turnOf(model.fen) ?? .white, choose: { piece in
                    let fen = model.fen
                    promotion = nil
                    if let move = BoardInteraction.promotion(fen, promoting.from, promoting.to, piece) { model.play(move) }
                }, cancel: { promotion = nil }).accessibilitySortPriority(4)
            }
            alternatives(tree, row: layout.short)
            if linesShown {
                EngineLinesView(lines: analyzer.lines, fen: model.fen, play: model.play, short: layout.short)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilitySortPriority(1)
            }
            commentCard(lines: layout.short ? 1 : 3)
            if !(layout.short && linesShown) {
                MoveListView(game: tree, path: model.path, go: model.go) { moveMenu($0) }
                    .frame(maxHeight: .infinity)
                    .accessibilitySortPriority(2)
            }
        }
        .accessibilityElement(children: .contain)
    }
    /// A stored game asks before its edits are left behind; a scratch one has nothing to save to.
    private var guardsLeaving: Bool { model.unsaved && scratch == nil }
    /// System toolbar items, no custom capsule (decision 13, F24): Flip Board and Engine
    /// Lines at the top, Previous / Next Move in the bottom bar. The system puts them in the
    /// side bar (O, SV, IL) or the navigation and bottom bars (IP, iPhone).
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if guardsLeaving {
            ToolbarItem(placement: .topBarLeading) { Button("Back", systemImage: "chevron.backward") { leaving = true }.accessibilityIdentifier("game-back") }
        }
        if model.tree != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Flip Board", systemImage: "arrow.up.arrow.down", action: model.flip).accessibilityIdentifier("game-flip-board")
            }
            ToolbarItem(placement: .topBarTrailing) { linesToggle }
            ToolbarItemGroup(placement: .bottomBar) {
                stepper("Previous Move", "chevron.left", hold: "Go to start", disabled: model.path.isEmpty, step: model.back) { model.go([]) }
                stepper("Next Move", "chevron.right", hold: "Go to end", disabled: model.following.isEmpty, step: model.next, jump: model.end)
            }
        }
    }
    /// Filled while the lines show; VoiceOver reads it as selected.
    @ViewBuilder private var linesToggle: some View {
        let button = Button("Engine Lines", systemImage: "list.bullet.indent") { withAnimation(.snappy) { linesShown.toggle() } }
            .accessibilityAddTraits(linesShown ? .isSelected : []).accessibilityIdentifier("game-engine-lines")
        if linesShown { button.buttonStyle(.borderedProminent).tint(.motifAccentStrong) } else { button }
    }
    /// A tap steps one move; holding jumps all the way. They stay plain toolbar buttons, so the
    /// system keeps them in the side bar (O, SV, IL): a button with its own style is a custom view,
    /// which the side bar leaves in a bottom bar over the content (ios-ci, fix loop 3). A bar item
    /// hands no gesture to SwiftUI, so the hold is read from the touch that triggered the action
    /// (`TouchClock`): held 0.4 s or longer, the release jumps instead of stepping.
    private func stepper(_ title: String, _ image: String, hold: String, disabled: Bool, step: @escaping () -> Void, jump: @escaping () -> Void) -> some View {
        Button(title, systemImage: image) {
            let held = TouchClock.held(atLeast: 0.4)
            Diag.log("stepper", "\(title) touch \(TouchClock.lastTouch.map { String(format: "%.2fs", $0) } ?? "none") → \(held ? "jump" : "step")")
            if held { jump() } else { step() }
        }
            .disabled(disabled)
            .accessibilityAction(named: hold) { if !disabled { jump() } }
            .accessibilityIdentifier("game-" + title.lowercased().replacingOccurrences(of: " ", with: "-"))
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
    /// Only a position with a comment shows the card; a tap opens the comment sheet.
    @ViewBuilder private func commentCard(lines: Int) -> some View {
        if !model.comment.isEmpty {
            Button { panel = .comment } label: {
                Text(model.comment).font(.subheadline).lineLimit(lines).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 12)
            }.buttonStyle(.plain)
                .motifGlass(in: .rect(cornerRadius: 14))
                .accessibilityIdentifier("game-comment")
        }
    }
    /// Alternatives to the current move, main line first, as 44 pt chips in the column, never
    /// over the board (F8, F9); capped at three until opened, and the cap always keeps the
    /// current move in view. `row`: one horizontally scrolling row (a short column).
    @ViewBuilder private func alternatives(_ tree: ParsedGame, row: Bool) -> some View {
        let parent = Array(model.path.dropLast())
        let siblings: [MoveNode] = model.path.isEmpty ? [] : parent.isEmpty ? tree.moves : nodeAt(tree, parent)?.children ?? []
        if siblings.count > 1, let current = model.path.last {
            let number = moveNumber(fenAt(tree, parent), true) ?? "", cap = 3
            let shown: [Int] = alternativesOpen || siblings.count <= cap ? Array(siblings.indices) : current < cap ? Array(0..<cap) : Array(0..<cap - 1) + [current]
            let chips = ForEach(shown, id: \.self) { index in
                let selected = index == current
                Button { model.go(parent + [index]) } label: {
                    HStack(spacing: 6) { if selected { Image(systemName: "checkmark").font(.caption.bold()).accessibilityHidden(true) }; Text(number + " " + siblings[index].san) }
                        .font(.subheadline.weight(selected ? .semibold : .regular)).foregroundStyle(selected ? Color.white : Color.primary)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                }.buttonStyle(.plain)
                    .motifGlass(tint: selected ? .motifAccentStrong : nil, interactive: true, in: .capsule)
                    .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("alternative-\(index)")
            }
            let toggle = Group {
                if siblings.count > cap {
                    Button { withAnimation(.snappy) { alternativesOpen.toggle() } } label: {
                        HStack(spacing: 4) { Text(alternativesOpen ? "Show less" : "+\(siblings.count - cap) more"); Image(systemName: alternativesOpen ? "chevron.up" : "chevron.down").accessibilityHidden(true) }
                            .font(.footnote.weight(.semibold)).foregroundStyle(Color.motifAccentStrong).padding(.horizontal, 12).frame(minHeight: 44)
                    }.buttonStyle(.plain).motifGlass(interactive: true, in: .capsule).accessibilityIdentifier("alternatives-toggle")
                }
            }
            Group {
                if row {
                    ScrollView(.horizontal) { HStack(spacing: 8) { chips; toggle } }.scrollIndicators(.hidden)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alternatives").font(.caption.weight(.semibold)).foregroundStyle(.motifSecondary).textCase(.uppercase)
                        FlowLayout(spacing: 8) { chips; toggle }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.transition(.opacity)
                .accessibilityElement(children: .contain).accessibilityLabel("Alternatives to this move")
        }
    }
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
/// How long the window's latest touch was held, for toolbar buttons that act differently on a
/// hold. A system bar item takes no SwiftUI gesture, but its action runs as its touch ends, so
/// the action asks here. A recognizer on the window watches every touch without taking any.
@MainActor enum TouchClock {
    fileprivate static var began: TimeInterval?
    fileprivate static var ended: TimeInterval?
    /// Whether the touch that just ended (or is still down) lasted `seconds` or more. A touch that
    /// ended a while ago didn't trigger this action (VoiceOver, keyboard), so it doesn't count.
    /// How long the touch that just ended (or is still down) has lasted, for diagnostics.
    static var lastTouch: TimeInterval? {
        guard let began else { return nil }
        return (ended ?? ProcessInfo.processInfo.systemUptime) - began
    }
    static func held(atLeast seconds: TimeInterval) -> Bool {
        guard let began else { return false }
        let now = ProcessInfo.processInfo.systemUptime, end = ended ?? now
        return now - end < 0.5 && end - began >= seconds
    }
}
private final class TouchClockRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// Watches without taking: no cancelled or delayed touches, and never blocks another recognizer.
    static func make() -> TouchClockRecognizer {
        let recognizer = TouchClockRecognizer(target: nil, action: nil)
        recognizer.cancelsTouchesInView = false; recognizer.delaysTouchesBegan = false; recognizer.delaysTouchesEnded = false
        recognizer.delegate = recognizer
        return recognizer
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        TouchClock.began = touch.timestamp; TouchClock.ended = nil
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { TouchClock.ended = touch.timestamp }
        state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        TouchClock.began = nil; TouchClock.ended = nil
        state = .failed
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
/// Puts one `TouchClockRecognizer` on the window this view is in.
private struct TouchClockInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { Probe() }
    func updateUIView(_ uiView: UIView, context: Context) {}
    private final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0 is TouchClockRecognizer }) else { return }
            window.addGestureRecognizer(TouchClockRecognizer.make())
        }
    }
}
