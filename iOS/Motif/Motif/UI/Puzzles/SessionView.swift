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
                    } else {
                        ContentUnavailableView {
                            Label("Session complete", systemImage: "checkmark.circle")
                        } description: {
                            Text("\(progress.solved) of \(progress.queue.count) solved cleanly\(progress.failed > 0 ? ", \(progress.failed) missed" : "").")
                        } actions: { Button("Done") { dismiss() } }
                    }
                } else { Color.clear.onAppear { dismiss() } }
            }.libraryBanners().navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Stop") { dismiss() }.accessibilityIdentifier("session-stop") } }
        }
    }
}
private struct SessionPuzzle: View {
    @Environment(AppState.self) private var app
    let puzzle: Puzzle
    let run: Run
    let progress: RunProgress
    @State private var model: SolveModel
    @State private var recording = false
    init(puzzle: Puzzle, run: Run, progress: RunProgress) {
        self.puzzle = puzzle; self.run = run; self.progress = progress
        _model = State(initialValue: SolveModel(puzzle))
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack { ProgressView(value: progress.progress); Text("\(progress.remaining) left").font(.caption).foregroundStyle(.secondary) }
                if puzzle.addPiece != nil { MissingPieceSolveView(model: model) { record(model.result, model.mistakes, model.hinted) } }
                else { PuzzleSolveView(model: model) { record(model.result, model.mistakes, model.hinted) } }
            }.padding()
        }
        // Scroll only when the result card overflows: a scroll view that always
        // bounces competes with piece drags for every vertical gesture.
        .scrollBounceBehavior(.basedOnSize)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(puzzle.flagged == true ? "Flagged" : "Flag") { Task { _ = await app.edit { try await $0.setFlagged(puzzle.id, puzzle.flagged != true) } } }.disabled(!app.store.online)
                Button("Skip") { model.cancel(); record(.skipped, 0, false) }.disabled(recording).accessibilityIdentifier("session-skip")
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
