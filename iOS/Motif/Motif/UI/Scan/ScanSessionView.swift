import SwiftUI

/// The open scan run, full screen. S04 starts and resumes runs; the steps themselves
/// (last move, quick scan, flag call, move, feedback) arrive with `ScanSolveModel` in S05.
struct ScanSessionView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let scope: String
    var body: some View {
        NavigationStack {
            Group {
                if let library = app.store.library, let run = scanRunIn(library, scope) {
                    let progress = scanProgressOf(library, run)
                    ContentUnavailableView("Session Ready", systemImage: "scope",
                                           description: Text("\(countLabel(progress.remaining, "puzzle")) to scan. Solving arrives in the next update."))
                        .accessibilityIdentifier("scan-session-placeholder")
                } else { Color.clear.onAppear { dismiss() } }
            }
            .libraryStatus().libraryMessages()
            .navigationTitle(scope == SCOPE_REVIEW ? "Review Mistakes" : "Scan").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }.accessibilityIdentifier("scan-session-done")
                }
            }
        }
    }
}
