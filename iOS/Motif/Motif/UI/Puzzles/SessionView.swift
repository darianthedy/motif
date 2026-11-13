import SwiftUI
struct SessionRoute: Identifiable { var scope: String; var id: String { scope } }

struct SessionView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let scope: String
    var body: some View {
        NavigationStack {
            Group {
                if let library = app.store.library, let run = runIn(library, scope) {
                    let progress = progressOf(library, run)
                    if let puzzle = library.puzzles.first(where: { $0.id == progress.current }) {
                        SessionPuzzle(puzzle: puzzle, run: run, progress: progress).id("\(puzzle.id):\(progress.played)")
                            .navigationSubtitle("Puzzle \(number(progress)) of \(progress.queue.count)")
                    } else {
                        SessionComplete(progress: progress) { dismiss() }
                    }
                } else { Color.clear.onAppear { dismiss() } }
            }.libraryStatus().libraryMessages().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("End Session", systemImage: "xmark") { dismiss() }.accessibilityIdentifier("session-stop")
                    }
                }
        }
    }
    private var title: String {
        switch scope {
        case SCOPE_ALL: "Random"
        case SCOPE_REVIEW: "Review Mistakes"
        default: app.store.library?.collections.first(where: { $0.id == scope })?.name ?? "Session"
        }
    }
    /// Retries keep `remaining` up, so the count stays inside the queue.
    private func number(_ progress: RunProgress) -> Int {
        min(max(progress.queue.count - progress.remaining + 1, 1), max(progress.queue.count, 1))
    }
}
private struct SessionPuzzle: View {
    @Environment(AppState.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    let puzzle: Puzzle
    let run: Run
    let progress: RunProgress
    @State private var model: SolveModel
    @State private var recording = false
    @State private var analyzing = false
    /// A promotion or a tapped square waiting for its piece, answered by the row in the layout (decision 17).
    @State private var pending: BoardPending?
    /// The content's size inside the safe area and the bars, for `BoardLayout`.
    @State private var container: CGSize = .zero
    /// The fold's active division, read under the progress bar where the board sits (D07).
    @State private var division: CGRect?
    /// The progress bar with its padding, which the board beside the column leaves out of its height.
    @State private var progressHeight: CGFloat = 0
    init(puzzle: Puzzle, run: Run, progress: RunProgress) {
        self.puzzle = puzzle; self.run = run; self.progress = progress
        #if DEBUG
        // `slow-reply` holds the opponent's reply long enough for a screenshot.
        if CaptureFixture.current.has("slow-reply") {
            _model = State(initialValue: SolveModel(puzzle) { try await Task.sleep(for: .milliseconds($0 == REPLY_MS ? 10_000 : $0)) })
            return
        }
        #endif
        _model = State(initialValue: SolveModel(puzzle))
    }
    private var flagged: Bool { puzzle.flagged == true }
    /// The result card's cap on compact width: 62 % of the content, scrolling past that (decision 15).
    private var cardCap: CGFloat { container.height > 0 ? container.height * 0.62 : .infinity }
    var body: some View {
        // The board is pinned: no scroll view around it, so solving never competes with
        // scrolling (decision 18, F2). One view tree in every pose: `AnyLayout` switches
        // between two panes and a stack, so `SolveModel` and a pending pick survive a fold.
        // On a fold the board takes the leading page or the top half, and the column (prompt,
        // pickers, result card) the other side; Skip is a bar item the system keeps off it (D07).
        let layout = boardLayout
        let stack = layout.sideBySide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: layout.spacing))
            : AnyLayout(VStackLayout(alignment: .center, spacing: layout.spacing))
        VStack(spacing: 0) {
            ProgressView(value: progress.progress).tint(.motifAccent)
                .padding(.leading, layout.padding.leading).padding(.trailing, layout.padding.trailing).padding(.vertical, 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { progressHeight = $0 }
                .accessibilityLabel("Session progress")
            stack {
                board.frame(width: layout.board, height: layout.board).accessibilitySortPriority(2)
                column(layout).accessibilitySortPriority(1)
            }
            .accessibilityElement(children: .contain)
            .padding(layout.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // In the stack's own coordinates, so the board's top is the layout's.
            .motifDivision($division)
            .accessibilitySortPriority(1)
        }
        // VoiceOver: the board, then the prompt, picker or result beside or under it (on
        // either page of a fold), then the progress bar, then the bar items (§6.14, D10).
        .accessibilityElement(children: .contain)
        // Measured with the progress bar, as the canvas sizes the boards (IP 512 pt); see `boardLayout`.
        .motifOfferedSize($container)
        // Compact width: the card still rises from the bottom, sized to its content (F5).
        .overlay(alignment: .bottom) {
            if model.done && layout.compact {
                resultCard.padding(.horizontal, 8).padding(.bottom, 8)
                    .frame(maxHeight: cardCap, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: model.done)
        // Pushed inside the session, so going back returns to this result; it carries its own capsule (F14).
        .navigationDestination(isPresented: $analyzing) { PuzzleAnalysisView(puzzle: puzzle).libraryStatus().libraryMessages() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(flagged ? "Unflag" : "Flag", systemImage: flagged ? "flag.fill" : "flag") {
                    Task { _ = await app.edit { try await $0.setFlagged(puzzle.id, !flagged) } }
                }.tint(flagged ? .orange : nil).disabled(!app.store.online).accessibilityIdentifier("session-flag")
            }
            // Skip is a system bottom bar item, not an overlay (decision 14, F24, F25): the side
            // bar on the Duo, the bottom bar on an iPhone.
            if !model.done {
                ToolbarItem(placement: .bottomBar) {
                    Button("Skip", systemImage: "forward.fill") { pending = nil; model.cancel(); record(.skipped, 0, false) }
                        .disabled(recording).accessibilityIdentifier("session-skip")
                }.motifHighVisibilityPriority()
            }
        }.onDisappear { model.cancel() }
            .task {
                #if DEBUG
                if app.launchRoute?.hasPrefix("result:") == true {
                    if let answer = puzzle.addPiece { model.submit(answer) }
                    else {
                        if app.launchRoute == "result:failed", let wrong = Board.targetsFrom(model.fen, "a1").keys.first(where: { $0 != "a8" }), let move = try? makeMove("a1", wrong) { model.submit(move) }
                        for (ply, move) in (puzzle.solutions.first ?? []).enumerated() where ply % 2 == 0 {
                            model.submit(move)
                            try? await Task.sleep(for: .milliseconds(REPLY_MS + 180))
                        }
                    }
                }
                #endif
            }
    }
    /// Stacked, the container includes the progress bar, as the canvas sizes the boards (IP 512 pt), and
    /// the column under the board gives up its 16 pt. Beside the column (IL, the iPad, a book fold) the
    /// board's height has nothing to give, so the progress bar comes off the container's height first.
    private var boardLayout: BoardLayout {
        let compact = sizeClass == .compact
        let full = BoardLayout(container: container, compact: compact, evalBar: false, division: division)
        guard full.sideBySide else { return full }
        let below = CGSize(width: container.width, height: max(0, container.height - progressHeight))
        return BoardLayout(container: below, compact: compact, evalBar: false, division: division)
    }
    @ViewBuilder private var board: some View {
        if puzzle.addPiece != nil { MissingPieceSolveView(model: model, pending: $pending) }
        else { PuzzleSolveView(model: model, pending: $pending) }
    }
    /// Under the board or beside it: the prompt, or the piece row while a pick is pending, or
    /// (except on compact width) the result card, at most 560 pt wide (decision 15). Stacked with
    /// room (IP), the card sits at the bottom of the column, below the board.
    private func column(_ layout: BoardLayout) -> some View {
        let panes = layout.sideBySide
        let alignment: Alignment = panes ? .topLeading : model.done && !layout.compact ? .bottom : .top
        return VStack(alignment: panes ? .leading : .center, spacing: 12) {
            if model.done {
                if !layout.compact { resultCard.frame(maxWidth: ResultCard.maxWidth).transition(.opacity) }
            } else if pending != nil {
                picker.frame(maxWidth: 380)
            } else {
                SolvePrompt(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
    private var resultCard: some View {
        ResultCard(model: model, analyze: { analyzing = true }) { record(model.result, model.mistakes, model.hinted) }
    }
    /// Promotion, or the missing piece for the tapped square. Choosing clears the pick first, so
    /// the board drops its selection whatever the answer (a wrong piece costs a guess, as before).
    @ViewBuilder private var picker: some View {
        switch pending {
        case .promotion(let from, let to)?:
            PieceRow(color: Board.turnOf(model.fen) ?? .white, choose: { piece in
                let fen = model.fen
                pending = nil
                if let move = BoardInteraction.promotion(fen, from, to, piece) { model.submit(move) }
            }, cancel: { pending = nil })
        case .placement(let square)?:
            if let color = puzzle.addPiece?.color {
                PieceRow(title: "Add on " + square, pieces: PieceRow.placement, color: color, choose: { piece in
                    pending = nil
                    if Board.pieceAt(model.fen, square) == nil { model.submit(Placement(color: color, type: piece, square: square)) }
                }, cancel: { pending = nil })
            }
        case nil:
            EmptyView()
        }
    }
    private func record(_ result: AttemptResult, _ mistakes: Int, _ hinted: Bool) {
        guard !recording else { return }; recording = true
        Task {
            do { try await app.store.recordAttempt(Attempt(id: newID(), puzzleId: puzzle.id, runId: run.id, result: result, mistakes: mistakes, hinted: hinted, playedAt: epochMilliseconds())) }
            catch { app.error = error.localizedDescription; recording = false }
        }
    }
}
private struct SessionComplete: View {
    static let maxWidth: CGFloat = 480
    @Environment(\.horizontalSizeClass) private var sizeClass
    let progress: RunProgress
    let done: () -> Void
    @State private var container: CGSize = .zero
    @State private var division: CGRect?
    var body: some View {
        // Content at most 480 pt wide, centred (F27). On a fold the heading takes the board's
        // side (the leading page, the top half) and the tiles and Done the other, so nothing
        // sits on the division (D07). One view tree: `AnyLayout` switches.
        let layout = BoardLayout(container: container, compact: sizeClass == .compact, evalBar: false, division: division)
        let folded = layout.mode == .pages || layout.mode == .halves
        // Across the division: from the board's side to the column's.
        let gap = layout.mode == .pages ? layout.column.minX - layout.boardSide.maxX : layout.column.minY - layout.boardSide.maxY
        let stack = layout.mode == .pages
            ? AnyLayout(HStackLayout(alignment: .center, spacing: gap))
            : AnyLayout(VStackLayout(alignment: .center, spacing: folded ? gap : 24))
        stack {
            VStack(spacing: 16) {
                if !folded { Spacer() }
                Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(Color.motifAccent).accessibilityHidden(true)
                Text("Session Complete").font(.title.bold())
            }
            .frame(width: layout.mode == .pages ? layout.boardSide.width : nil, height: layout.mode == .halves ? layout.boardSide.height : nil)
            .frame(maxHeight: layout.mode == .pages ? .infinity : nil)
            VStack(spacing: 24) {
                // Stacked at accessibility sizes, where two tiles leave no room for their labels.
                RowStack(spacing: 12) {
                    tile(progress.solved, "Solved cleanly", .motifAccentStrong)
                    tile(progress.failed, "Missed", .orange)
                }.padding(.horizontal)
                Spacer()
                Button(action: done) { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent).controlSize(.large).padding()
                    .accessibilityIdentifier("session-done")
            }
            .frame(maxWidth: SessionComplete.maxWidth).frame(maxWidth: .infinity, maxHeight: folded ? .infinity : nil)
        }
        .padding(folded ? layout.padding : EdgeInsets())
        .frame(maxWidth: folded ? .infinity : SessionComplete.maxWidth).frame(maxWidth: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { container = $0 }
        .motifDivision($division)
    }
    private func tile(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.largeTitle.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.subheadline).foregroundStyle(.motifSecondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }
}
