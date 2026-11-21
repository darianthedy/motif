import SwiftUI

/// One scan puzzle in a session (Scan plan §6): the run's progress and the step's time on top,
/// the board, the step's prompt or feedback beside or under it, and the step's actions at the
/// bottom. Its `ScanSolveModel` lives as long as the puzzle does; the attempt is recorded as the
/// result shows, so closing the session there keeps it (playtest 4), and the session holds the
/// puzzle on screen until Continue, when `runProgress` names the next one.
struct ScanSessionPuzzle: View {
    @Environment(AppState.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    let puzzle: ScanPuzzle
    let run: Run
    /// Serves done out of the total, retries included: moves after every pass or fail.
    let progress: RunPosition
    @Binding var measured: SessionMeasurements
    /// The result is showing and about to be recorded: the session holds this puzzle.
    let onResult: () -> Void
    /// Continue from a recorded result: the session moves on.
    let onContinue: () -> Void
    @State private var model: ScanSolveModel
    @State private var recording = false
    /// The result's attempt, made once so a retried save keeps its id; set once it's stored.
    @State private var resultAttempt: ScanAttempt?
    @State private var saved = false
    /// A promotion waiting for its piece, answered by the row in the column.
    @State private var pending: BoardPending?
    /// The Legend sheet: what each miss icon means.
    @State private var showsLegend = false
    init(puzzle: ScanPuzzle, run: Run, progress: RunPosition, limits: ScanLimits = ScanLimits(),
         measured: Binding<SessionMeasurements>, onResult: @escaping () -> Void = {}, onContinue: @escaping () -> Void = {}) {
        self.puzzle = puzzle; self.run = run; self.progress = progress; _measured = measured
        self.onResult = onResult; self.onContinue = onContinue
        _model = State(initialValue: ScanSolveModel(puzzle, limits: limits, autoAdvanceMs: ScanSolveModel.configuredAutoAdvanceMs))
    }
    var body: some View {
        // As in `SessionPuzzle`: one view tree in every pose, the board pinned (no scroll view
        // around it), the column beside it on regular width or a fold and under it otherwise.
        let layout = boardLayout
        let stack = layout.sideBySide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: layout.spacing))
            : AnyLayout(VStackLayout(alignment: .center, spacing: layout.spacing))
        // Side by side (IL, iPad landscape) the header and the actions move into the column, so the
        // board takes the whole height: it was capped by them, with the column beside it mostly
        // empty (playtest 3). Stacked, they stay above and under everything.
        VStack(spacing: 0) {
            if !layout.sideBySide { header(layout) }
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
        .safeAreaInset(edge: .bottom) {
            if !layout.sideBySide { actions.padding(.horizontal, layout.padding.leading).padding(.bottom, 8) }
        }
        .navigationTitle(model.step.title)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Legend", systemImage: "info") { showsLegend = true }.accessibilityIdentifier("scan-legend")
            }
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
        .sheet(isPresented: $showsLegend) { ScanLegendSheet(step: model.step) }
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
            AccessibilityNotification.Announcement([next.title, next.spokenReason].filter { !$0.isEmpty }.joined(separator: ". ")).post()
        }
        // A limit that runs out mid-promotion ends the move: the piece row goes with it.
        .onChange(of: model.step) { pending = nil }
        .onChange(of: model.outcome != nil) { _, done in if done { saveResult() } }
        .onAppear { model.attach(undoManager); model.autoAdvance = !voiceOver && !switchControl }
        .onChange(of: voiceOver || switchControl) { _, assistive in model.autoAdvance = !assistive }
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
        let inset = layout.sideBySide ? EdgeInsets() : EdgeInsets(top: 0, leading: layout.padding.leading, bottom: 0, trailing: layout.padding.trailing)
        return HStack(spacing: 12) {
            ProgressView(value: progress.fraction).tint(.motifAccent).accessibilityLabel("Session progress")
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
        .padding(.leading, inset.leading).padding(.trailing, inset.trailing).padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if let started = model.stepStarted, let deadline = model.deadline, started < deadline {
                ProgressView(timerInterval: started...deadline, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(.orange)
                    .accessibilityLabel("Time limit")
                    .accessibilityIdentifier("scan-limit")
                    .padding(.leading, inset.leading).padding(.trailing, inset.trailing)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if measured.progressHeight != $0 { measured.progressHeight = $0 } }
    }

    private var board: some View {
        BoardView(fen: model.fen, orientation: model.solver, interactive: model.boardInteractive,
                  highlight: model.highlight, onMove: { model.play($0) }, pending: $pending,
                  mode: model.boardMode, annotations: model.annotations, onSquare: { model.tap($0) },
                  onSquares: { model.markTargets($0) }, onArrow: { model.drawArrow(from: $0, to: $1) })
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
        let scrolling = ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.sideBySide ? .topLeading : .top)
        .animation(.smooth, value: model.feedback)
        return VStack(spacing: 12) {
            if layout.sideBySide { header(layout) }
            scrolling
            if layout.sideBySide { actions.frame(maxWidth: ResultCard.maxWidth) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Tactic / Quiet while scanning, Next on the arrows, Take Back / Play It on the
    /// final check, Continue on feedback.
    /// Neither call is prominent, so the buttons never hint at the answer; stacked at
    /// accessibility text sizes. Hidden copies of the tallest rows keep the row's height between
    /// steps, so the board doesn't change size under them: the glass calls stand a little taller
    /// than the prominent Continue, and the board, sized in whole squares, jumped 8 pt for it.
    private var actions: some View {
        ZStack {
            continueButton.hidden().accessibilityHidden(true)
            callRow.hidden().accessibilityHidden(true)
            if model.feedback != nil {
                continueButton
            } else if model.canMark, model.step != .quickScan {
                Button { model.finishStep() } label: { Label("Next", systemImage: "checkmark").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("scan-next")
            } else if model.canMark {
                callRow
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

    private var callRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { calls }
            VStack(spacing: 12) { calls }
        }
    }

    @ViewBuilder private var calls: some View {
        Button { model.call(false) } label: { Label("Quiet", systemImage: "leaf").frame(maxWidth: .infinity) }
            .buttonStyle(.glass).controlSize(.large).disabled(!model.canCallNoFlag).accessibilityIdentifier("scan-no-flag")
        Button { model.call(true) } label: { Label("Tactic", systemImage: "bolt.fill").frame(maxWidth: .infinity) }
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
        if saved { onContinue() } else { saveResult(thenContinue: true) }
    }

    /// The result is saved as it shows. A save that failed is tried again on Continue.
    private func saveResult(thenContinue: Bool = false) {
        if resultAttempt == nil { resultAttempt = model.attempt(runId: run.id, playedAt: epochMilliseconds()) }
        guard let attempt = resultAttempt else { return }
        onResult()
        record(attempt) { saved = true; if thenContinue { onContinue() } }
    }

    /// A puzzle whose fail is already shown (a wrong Quiet) is recorded as that fail, not as a
    /// skip, so it still goes to review (playtest 4).
    private func skip() {
        pending = nil
        let playedAt = epochMilliseconds()
        let attempt = model.settledAttempt(runId: run.id, playedAt: playedAt)
            ?? .skip(puzzleId: puzzle.id, runId: run.id, playedAt: playedAt)
        model.cancel()
        record(attempt)
    }

    /// Through the outbox, so it works offline and uploads when it can.
    private func record(_ attempt: ScanAttempt, then done: @escaping () -> Void = {}) {
        guard !recording else { return }; recording = true
        Task {
            do { try await app.store.recordScanAttempt(attempt); recording = false; done() }
            catch { app.error = error.localizedDescription; recording = false }
        }
    }

    // MARK: Layout

    private func changing<Value: Equatable>(_ path: WritableKeyPath<SessionMeasurements, Value>) -> Binding<Value> {
        Binding(get: { measured[keyPath: path] }, set: { if measured[keyPath: path] != $0 { measured[keyPath: path] = $0 } })
    }

    /// As `SessionPuzzle`'s, but beside the column the header and the actions are in the column,
    /// so nothing comes off the board's height.
    private var boardLayout: BoardLayout {
        BoardLayout(container: measured.container, compact: sizeClass == .compact, evalBar: false, division: measured.division)
    }
}
