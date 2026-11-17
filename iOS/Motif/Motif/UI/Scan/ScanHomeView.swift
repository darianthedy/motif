import SwiftUI

/// The Scan tab's root (Scan plan §6): the pool's Solved / To review / New card, an open
/// session or Start, Review Mistakes, All Puzzles; Import and Reset in the toolbar menu.
struct ScanHomeView: View {
    @Environment(AppState.self) private var app
    @State private var resetting = false
    var body: some View {
        ZStack {
            if let library = app.store.library, !library.scanPuzzles.isEmpty {
                content(library)
            } else {
                EmptyState(title: "No Scan Puzzles Yet", systemImage: "scope",
                           description: "Import a scan file, or have Caïssa send puzzles to your account.",
                           action: .init(title: "Import Scan Puzzles", identifier: "scan-import-empty", disabled: !app.store.online) { app.importingScan = true })
                    .readableWidth()
            }
        }
        .navigationTitle("Scan")
        .navigationSubtitle(app.store.library.map { $0.scanPuzzles.isEmpty ? "" : countLabel($0.scanPuzzles.count, "puzzle") } ?? "")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Scan Actions", systemImage: "ellipsis") {
                    Button("Import Scan Puzzles…", systemImage: "square.and.arrow.down") { app.importingScan = true }
                        .disabled(!app.store.online)
                    Divider()
                    Button("Reset Scan Progress…", systemImage: "arrow.counterclockwise", role: .destructive) { resetting = true }
                        .disabled(!app.store.online || app.store.library?.scanAttempts.isEmpty != false && app.store.library?.scanRuns.isEmpty != false)
                }.accessibilityIdentifier("scan-actions")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) { AccountButton() }.motifHighVisibilityPriority()
        }
        .confirmationDialog("Reset scan progress?", isPresented: $resetting, titleVisibility: .visible) {
            Button("Reset Scan Progress", role: .destructive) {
                Task { _ = await app.edit({ try await $0.resetScanProgress() }, done: "Scan progress reset.") }
            }
        } message: {
            Text("Every scan session and result is deleted. The puzzles and your Puzzles progress stay.")
        }
    }
    private func content(_ library: Library) -> some View {
        let review = scanReviewIds(library)
        let openAll = scanResumable(library, SCOPE_ALL) ? scanRunIn(library, SCOPE_ALL) : nil
        let openReview = scanResumable(library, SCOPE_REVIEW) ? scanRunIn(library, SCOPE_REVIEW) : nil
        return List {
            Section { StatsCard(stats: scanStats(library)) }
            if let run = openAll { session("Session in Progress", run, library, identifier: "scan-session") }
            if let run = openReview { session("Review in Progress", run, library, identifier: "scan-review") }
            if openAll == nil {
                Section {
                    Button { Task { await app.beginScan(SCOPE_ALL, .randomGlobal) } } label: {
                        Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).controlSize(.large)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("scan-start")
                }
            }
            Section {
                Button { Task { await app.beginScan(SCOPE_REVIEW, .reviewMistakes) } } label: {
                    LabeledContent {
                        if !review.isEmpty { Text("\(review.count)").monospacedDigit() }
                    } label: { Label("Review Mistakes", systemImage: "arrow.counterclockwise") }
                }
                .disabled(review.isEmpty).accessibilityIdentifier("scan-review-mistakes")
            }
            Section {
                NavigationLink(value: ScanRoute.puzzles) {
                    LabeledContent { Text("\(library.scanPuzzles.count)").monospacedDigit() } label: { Label("All Puzzles", systemImage: "square.grid.2x2") }
                }.accessibilityIdentifier("scan-all-puzzles")
            }
        }
    }
    private func session(_ title: String, _ run: Run, _ library: Library, identifier: String) -> some View {
        SessionRow(title: title, remaining: scanProgressOf(library, run).remaining, online: app.store.online, identifier: identifier,
                   resume: { app.scanSession = ScanSessionRoute(scope: run.scope) },
                   discard: { Task { _ = await app.edit { try await $0.deleteScanRun(run.id) } } })
    }
}
