import SwiftUI

/// One scan puzzle in a session (Scan plan §6): the run's progress and the step's time on top,
/// the board, the step's prompt or feedback beside or under it, and the step's actions at the
/// bottom. Its `ScanSolveModel` lives as long as the puzzle does; the attempt is recorded when
/// the result is continued from, and `runProgress` then names the next puzzle.
struct ScanSessionPuzzle: View {
    @Environment(AppState.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.undoManager) private var undoManager
    let puzzle: ScanPuzzle
    let run: Run
    let progress: RunProgress
    @Binding var measured: SessionMeasurements
    @State private var model: ScanSolveModel
    @State private var recording = false
    /// A promotion waiting for its piece, answered by the row in the column.
    @State private var pending: BoardPending?
    init(puzzle: ScanPuzzle, run: Run, progress: RunProgress, limits: ScanLimits = ScanLimits(),
         measured: Binding<SessionMeasurements>) {
        self.puzzle = puzzle; self.run = run; self.progress = progress; _measured = measured
        _model = State(initialValue: ScanSolveModel(puzzle, limits: limits))
    }
    var body: some View {
        // As in `SessionPuzzle`: one view tree in every pose, the board pinned (no scroll view
        // around it), the column beside it on regular width or a fold and under it otherwise.
        let layout = boardLayout
        let stack = layout.sideBySide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: layout.spacing))
            : AnyLayout(VStackLayout(alignment: .center, spacing: layout.spacing))
        VStack(spacing: 0) {
            header(layout)
            stack {
                board.frame(width: layout.board, height: layout.board).accessibilitySortPriority(2)
                column(layout).accessibilitySortPriority(1)
            }
            .accessibilityElement(children: .contain)
            .padding(layout.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .motifDivision(changing(\.division))
        }
        .accessibilityElement(children: .contain)
        .motifOfferedSize(changing(\.container))
        .safeAreaInset(edge: .bottom) { actions.padding(.horizontal, layout.padding.leading).padding(.bottom, 8) }
        .navigationTitle(model.step.title)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                    .disabled(!model.canUndo).accessibilityIdentifier("scan-undo")
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            // Stays (disabled) on the result, so the bar doesn't leave and resize the screen.
            ToolbarItem(placement: .bottomBar) {
                Button("Skip", systemImage: "forward.fill") { skip() }
                    .disabled(recording || model.outcome != nil).accessibilityIdentifier("scan-skip")
            }.motifHighVisibilityPriority()
        }
        .sensoryFeedback(trigger: model.feedback) { _, next in
            switch next?.verdict {
            case .pass?: .success
            case .softMiss?: .warning
            case .fail?: .error
            case nil: nil
            }
        }
        .onChange(of: model.feedback) { _, next in
            guard let next else { return }
            AccessibilityNotification.Announcement([next.title, next.reason].filter { !$0.isEmpty }.joined(separator: ". ")).post()
        }
        // A limit that runs out mid-promotion ends the move: the piece row goes with it.
        .onChange(of: model.step) { pending = nil }
        .onAppear { model.attach(undoManager) }
        .onChange(of: undoManager) { _, next in model.attach(next) }
        .onDisappear { model.cancel() }
        .task { await model.begin() }
    }

    // MARK: Parts

    /// The run's progress, and the step's time beside it: elapsed while record-only, counting
    /// down under a hard limit, with the limit's bar along the header's bottom edge (in its
    /// padding, so the header is the same height with or without one and the board never
    /// moves). Both draw themselves from the step's start and deadline: the model never ticks.
    private func header(_ layout: BoardLayout) -> some View {
        HStack(spacing: 12) {
            ProgressView(value: progress.progress).tint(.motifAccent).accessibilityLabel("Session progress")
            Group {
                if let started = model.stepStarted, let deadline = model.deadline, started < deadline {
                    Text(timerInterval: started...deadline, countsDown: true).accessibilityLabel("Time left")
                } else if let started = model.stepStarted {
                    Text(started, style: .timer).accessibilityLabel("Time on this step")
                } else {
                    Text("0:00").hidden().accessibilityHidden(true)
                }
            }
            .font(.subheadline.monospacedDigit()).foregroundStyle(.motifSecondary)
            .accessibilityIdentifier("scan-timer")
        }
        .padding(.leading, layout.padding.leading).padding(.trailing, layout.padding.trailing).padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if let started = model.stepStarted, let deadline = model.deadline, started < deadline {
                ProgressView(timerInterval: started...deadline, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(.orange)
                    .accessibilityLabel("Time limit")
                    .accessibilityIdentifier("scan-limit")
                    .padding(.leading, layout.padding.leading).padding(.trailing, layout.padding.trailing)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if measured.progressHeight != $0 { measured.progressHeight = $0 } }
    }

    private var board: some View {
        BoardView(fen: model.fen, orientation: model.solver, interactive: model.boardInteractive,
                  highlight: model.highlight, onMove: { model.play($0) }, pending: $pending,
                  mode: model.boardMode, annotations: model.annotations, onSquare: { model.tap($0) },
                  onSquares: { model.markTargets($0) }, onArrow: { model.drawArrow(from: $0, to: $1) },
                  onArrowTap: { model.removeArrow(at: $0) })
    }

    /// The step's prompt, the promotion row, or the feedback. Scrolls only when the text is too
    /// tall for the room left, at the largest text sizes.
    private func column(_ layout: BoardLayout) -> some View {
        let content = VStack(alignment: layout.sideBySide ? .leading : .center, spacing: 12) {
            if let feedback = model.feedback {
                ScanFeedbackView(feedback: feedback).frame(maxWidth: ResultCard.maxWidth)
            } else if case .promotion(let from, let to)? = pending {
                PieceRow(color: model.solver, choose: { piece in
                    let fen = model.fen
                    pending = nil
                    if let move = BoardInteraction.promotion(fen, from, to, piece) { model.play(move) }
                }, cancel: { pending = nil }).frame(maxWidth: 380)
            } else {
                // The drawn arrows come first: on a short column (the iPhone Duo's cover screen) the
                // prompt, already read, is what scrolls away, not the buttons that delete arrows.
                if model.step == .arrows {
                    ScanArrowList(arrows: model.current.arrows, fen: model.fen) { model.removeArrow(at: $0) }
                        .frame(maxWidth: ResultCard.maxWidth, alignment: layout.sideBySide ? .leading : .center)
                }
                SolvePrompt(side: model.solver, guidance: model.prompt).accessibilityIdentifier("scan-prompt")
            }
        }
        return ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.sideBySide ? .topLeading : .top)
        .animation(.smooth, value: model.feedback)
    }

    /// Flag / No Flag while scanning, Next on the targets and arrows, Take Back / Play It on the
    /// final check, Continue on feedback.
    /// Neither call is prominent, so the buttons never hint at the answer; stacked at
    /// accessibility text sizes. A hidden button keeps the row's height between steps, so the
    /// board doesn't change size under them.
    private var actions: some View {
        ZStack {
            continueButton.hidden().accessibilityHidden(true)
            if model.feedback != nil {
                continueButton
            } else if model.canMark, model.step != .quickScan {
                Button { model.finishStep() } label: { Label("Next", systemImage: "checkmark").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("scan-next")
            } else if model.canMark {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { calls }
                    VStack(spacing: 12) { calls }
                }
            } else if model.step == .finalCheck {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { finalCheck }
                    VStack(spacing: 12) { finalCheck }
                }
            }
        }
    }

    private var continueButton: some View {
        Button { next() } label: { Label("Continue", systemImage: "arrow.right").frame(maxWidth: .infinity) }
            .buttonStyle(.glassProminent).controlSize(.large)
            .disabled(recording).accessibilityIdentifier("scan-continue")
    }

    @ViewBuilder private var calls: some View {
        Button { model.call(false) } label: { Label("No Flag", systemImage: "flag.slash").frame(maxWidth: .infinity) }
            .buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("scan-no-flag")
        Button { model.call(true) } label: { Label("Flag", systemImage: "flag.fill").frame(maxWidth: .infinity) }
            .buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("scan-flag")
    }

    /// The move waits, ghosted, for one of these (Puzzle flow 6).
    @ViewBuilder private var finalCheck: some View {
        Button { model.takeBack() } label: { Label("Take Back", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
            .buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("scan-take-back")
        Button { model.confirm() } label: { Label("Play It", systemImage: "checkmark").frame(maxWidth: .infinity) }
            .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("scan-play-it")
    }

    // MARK: Actions

    private func next() {
        if model.outcome == nil { model.proceed(); return }
        guard let attempt = model.attempt(runId: run.id, playedAt: epochMilliseconds()) else { return }
        record(attempt)
    }

    private func skip() {
        pending = nil; model.cancel()
        record(.skip(puzzleId: puzzle.id, runId: run.id, playedAt: epochMilliseconds()))
    }

    /// Through the outbox, so it works offline and uploads when it can.
    private func record(_ attempt: ScanAttempt) {
        guard !recording else { return }; recording = true
        Task {
            do { try await app.store.recordScanAttempt(attempt) }
            catch { app.error = error.localizedDescription; recording = false }
        }
    }

    // MARK: Layout

    private func changing<Value: Equatable>(_ path: WritableKeyPath<SessionMeasurements, Value>) -> Binding<Value> {
        Binding(get: { measured[keyPath: path] }, set: { if measured[keyPath: path] != $0 { measured[keyPath: path] = $0 } })
    }

    /// As `SessionPuzzle`'s: beside the column the header comes off the board's height first.
    private var boardLayout: BoardLayout {
        let compact = sizeClass == .compact
        let full = BoardLayout(container: measured.container, compact: compact, evalBar: false, division: measured.division)
        guard full.sideBySide else { return full }
        let below = CGSize(width: measured.container.width, height: max(0, measured.container.height - measured.progressHeight))
        return BoardLayout(container: below, compact: compact, evalBar: false, division: measured.division)
    }
}
