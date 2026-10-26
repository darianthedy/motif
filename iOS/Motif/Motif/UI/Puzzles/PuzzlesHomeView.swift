import SwiftUI

enum PuzzleRoute: Hashable { case collection(String), puzzles(String), puzzle(String, String) }
struct PuzzlesHomeView: View {
    @Environment(AppState.self) private var app
    @State private var resetting = false
    var body: some View {
        @Bindable var app = app
        List {
            if let library = app.store.library {
                let records = puzzleRecords(library.attempts)
                Section {
                    if library.puzzles.isEmpty { Text("Nothing here yet. Import a collection to start.").foregroundStyle(.secondary) }
                    else { Text("\(countLabel(library.puzzles.count, "puzzle")) in \(countLabel(library.collections.count, "collection"))").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(collectionsOf(library), id: \.id) { collection in
                        let stats = statsFor(puzzlesIn(library, collection.id).map(\.id), records)
                        NavigationLink(value: PuzzleRoute.collection(collection.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(collection.name); if resumable(library, collection.id) { Text("in progress").font(.caption).foregroundStyle(Color.motifAccent) } }
                                Text("\(countLabel(stats.total, "puzzle")) · \(stats.solved) solved\(stats.failed > 0 ? " · \(stats.failed) to review" : "")").font(.footnote).foregroundStyle(.secondary)
                                ProgressView(value: stats.total > 0 ? Double(stats.solved) / Double(stats.total) : 0)
                            }
                        }.accessibilityIdentifier("collection-" + collection.id)
                    }
                }
                if !library.puzzles.isEmpty {
                    Section {
                        if resumable(library, SCOPE_ALL) { Button("Resume random session") { app.session = SessionRoute(scope: SCOPE_ALL) } }
                        Button("Random from everything") {
                            Task { await app.begin(SCOPE_ALL, .randomGlobal, orderForGlobalDraw(allPuzzles(library).map(\.id), recentIds(library.attempts))) }
                        }.accessibilityIdentifier("solve-all")
                        let review = reviewIds(allPuzzles(library).map(\.id), records)
                        Button("Review mistakes\(review.isEmpty ? "" : " (\(review.count))")") { Task { await app.begin(SCOPE_REVIEW, .reviewMistakes, review) } }.disabled(review.isEmpty)
                    }
                }
            }
            Section {
                Button("Import puzzles") { app.importingPuzzles = true }.disabled(!app.store.online).accessibilityIdentifier("import-puzzles")
                Button("Reset progress", role: .destructive) { resetting = true }.disabled(!app.store.online || app.store.library?.attempts.isEmpty != false)
            }
        }.navigationTitle("Puzzles")
            .sheet(isPresented: $app.importingPuzzles) { ImportView().environment(app) }
            .confirmationDialog("Forget every attempt? Your puzzles and collections stay. Solved, mistakes and in-progress sessions are cleared on every device.", isPresented: $resetting, titleVisibility: .visible) {
                Button("Reset progress", role: .destructive) { Task { _ = await app.edit({ try await $0.resetProgress() }, done: "Progress reset. Every puzzle is unseen again.") } }
            }
            .fullScreenCover(item: $app.session) { SessionView(scope: $0.scope).environment(app) }
            .task { await openLaunchRoute() }
    }
    private func openLaunchRoute() async {
        #if DEBUG
        guard let route = app.launchRoute, let library = app.store.library else { return }
        if route == "import" { app.importingPuzzles = true }
        if route == "puzzle-list", let first = library.collections.first { app.puzzlesPath = [.collection(first.id), .puzzles(first.id)] }
        if route == "puzzle-detail", let first = library.collections.first, let puzzle = puzzlesIn(library, first.id).first { app.puzzlesPath = [.collection(first.id), .puzzles(first.id), .puzzle(first.id, puzzle.id)] }
        if route == "collection", let first = library.collections.first { app.puzzlesPath = [.collection(first.id)] }
        if route.hasPrefix("session:") || route.hasPrefix("result:") {
            let scope = route == "session:missing" ? "sample-missing-piece" : SCOPE_ALL
            let puzzles = scope == SCOPE_ALL ? allPuzzles(library) : puzzlesIn(library, scope)
            await app.begin(scope, .ordered, puzzles.map(\.id))
        }
        #endif
    }
}
