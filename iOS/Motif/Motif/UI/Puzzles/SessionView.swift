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
            }.libraryBanners().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
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
    let puzzle: Puzzle
    let run: Run
    let progress: RunProgress
    @State private var model: SolveModel
    @State private var recording = false
    @State private var analyzing = false
    init(puzzle: Puzzle, run: Run, progress: RunProgress) {
        self.puzzle = puzzle; self.run = run; self.progress = progress
        _model = State(initialValue: SolveModel(puzzle))
    }
    private var flagged: Bool { puzzle.flagged == true }
    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: progress.progress).tint(.motifAccent).padding(.horizontal).padding(.vertical, 6)
                .accessibilityLabel("Session progress")
            ScrollView {
                if puzzle.addPiece != nil { MissingPieceSolveView(model: model) }
                else { PuzzleSolveView(model: model) }
            }
            // Scroll only when the content overflows: a scroll view that always
            // bounces competes with piece drags for every vertical gesture.
            .scrollBounceBehavior(.basedOnSize)
        }
        .overlay(alignment: .bottomTrailing) {
            if !model.done {
                Button("Skip", systemImage: "forward.fill") { model.cancel(); record(.skipped, 0, false) }
                    .buttonStyle(.glass).controlSize(.large).disabled(recording)
                    .padding().accessibilityIdentifier("session-skip")
            }
        }
        .overlay(alignment: .bottom) {
            if model.done {
                ResultCard(model: model, analyze: { analyzing = true }) { record(model.result, model.mistakes, model.hinted) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: model.done)
        // Pushed inside the session, so going back returns to this result.
        .navigationDestination(isPresented: $analyzing) { PuzzleAnalysisView(puzzle: puzzle) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(flagged ? "Unflag" : "Flag", systemImage: flagged ? "flag.fill" : "flag") {
                    Task { _ = await app.edit { try await $0.setFlagged(puzzle.id, !flagged) } }
                }.tint(flagged ? .orange : nil).disabled(!app.store.online).accessibilityIdentifier("session-flag")
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
    private func record(_ result: AttemptResult, _ mistakes: Int, _ hinted: Bool) {
        guard !recording else { return }; recording = true
        Task {
            do { try await app.store.recordAttempt(Attempt(id: newID(), puzzleId: puzzle.id, runId: run.id, result: result, mistakes: mistakes, hinted: hinted, playedAt: epochMilliseconds())) }
            catch { app.error = error.localizedDescription; recording = false }
        }
    }
}
private struct SessionComplete: View {
    let progress: RunProgress
    let done: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(Color.motifAccent).accessibilityHidden(true)
            Text("Session Complete").font(.title.bold())
            HStack(spacing: 12) {
                tile(progress.solved, "Solved cleanly", .motifAccentStrong)
                tile(progress.failed, "Missed", .orange)
            }.padding(.horizontal)
            Spacer()
            Button(action: done) { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).controlSize(.large).padding()
                .accessibilityIdentifier("session-done")
        }.frame(maxWidth: .infinity)
    }
    private func tile(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.largeTitle.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }
}
