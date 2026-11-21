import SwiftUI

/// The open scan run, full screen (Scan plan §6): one `ScanSessionPuzzle` per puzzle, chosen by
/// `runProgress` from the run's attempts, so leaving and coming back resumes at the same puzzle.
struct ScanSessionView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let scope: String
    /// Kept across puzzles, as `SessionView` does, so each new puzzle starts at the right size.
    @State private var measured = SessionMeasurements()
    /// The puzzle whose result is on screen. Its attempt is saved as the result shows (playtest
    /// 4: closing there lost it), which moves the run on; the puzzle stays until Continue.
    @State private var held: Shown?
    @AppStorage(ScanTimeLimitsPreference.key) private var timeLimitsStored: Bool?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    var body: some View {
        NavigationStack {
            Group {
                if let library = app.store.library, let run = scanRunIn(library, scope) {
                    let progress = scanProgressOf(library, run)
                    if let shown = held ?? library.scanPuzzles.first(where: { $0.id == progress.current }).map({
                        Shown(puzzle: $0, position: scanPositionOf(library, run), key: "\($0.id):\(progress.played)")
                    }) {
                        // Fixed when the puzzle starts: a change to the switch applies from the next.
                        ScanSessionPuzzle(puzzle: shown.puzzle, run: run, progress: shown.position, limits: limits(library),
                                          measured: $measured,
                                          onResult: { held = shown }, onContinue: { held = nil })
                            .id(shown.key)
                            .navigationSubtitle("Puzzle \(shown.position.number) of \(shown.position.total)")
                    } else {
                        SessionComplete(progress: progress, solvedLabel: "Passed", failedLabel: "Failed") { dismiss() }
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
    /// The puzzle on screen, where the run stood when it started.
    private struct Shown { var puzzle: ScanPuzzle; var position: RunPosition; var key: String }

    private func limits(_ library: Library) -> ScanLimits {
        let enabled = ScanTimeLimitsPreference.enabled(stored: timeLimitsStored, voiceOver: voiceOver, switchControl: switchControl)
        return ScanTiming.limits(library.scanAttempts, now: epochMilliseconds(), enabled: enabled)
    }
}
