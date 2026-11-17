import SwiftUI

/// The open scan run, full screen (Scan plan §6): one `ScanSessionPuzzle` per puzzle, chosen by
/// `runProgress` from the run's attempts, so leaving and coming back resumes at the same puzzle.
struct ScanSessionView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let scope: String
    /// Kept across puzzles, as `SessionView` does, so each new puzzle starts at the right size.
    @State private var measured = SessionMeasurements()
    var body: some View {
        NavigationStack {
            Group {
                if let library = app.store.library, let run = scanRunIn(library, scope) {
                    let progress = scanProgressOf(library, run)
                    if let puzzle = library.scanPuzzles.first(where: { $0.id == progress.current }) {
                        ScanSessionPuzzle(puzzle: puzzle, run: run, progress: progress, measured: $measured)
                            .id("\(puzzle.id):\(progress.played)")
                            .navigationSubtitle("Puzzle \(number(progress)) of \(progress.queue.count)")
                    } else {
                        SessionComplete(progress: progress, solvedLabel: "Passed") { dismiss() }
                            .navigationTitle(scope == SCOPE_REVIEW ? "Review Mistakes" : "Scan")
                    }
                } else { Color.clear.onAppear { dismiss() } }
            }
            .libraryStatus().libraryMessages()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Ends the session; finished puzzles are already saved.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }.accessibilityIdentifier("scan-session-done")
                }
            }
        }
    }
    /// Retries keep `remaining` up, so the count stays inside the queue.
    private func number(_ progress: RunProgress) -> Int {
        min(max(progress.queue.count - progress.remaining + 1, 1), max(progress.queue.count, 1))
    }
}
