import SwiftUI

enum PuzzleRoute: Hashable { case collection(String) }
struct PuzzlesHomeView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        @Bindable var app = app
        List {
            if let library = app.store.library {
                let records = puzzleRecords(library.attempts)
                Section {
                    if library.puzzles.isEmpty { Text("Nothing here yet. Import a collection to start.").foregroundStyle(.secondary) }
                    else { Text("\(library.puzzles.count) puzzles in \(library.collections.count) collections").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(collectionsOf(library), id: \.id) { collection in
                        let stats = statsFor(puzzlesIn(library, collection.id).map(\.id), records)
                        NavigationLink(value: PuzzleRoute.collection(collection.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(collection.name); if resumable(library, collection.id) { Text("in progress").font(.caption).foregroundStyle(Color.motifAccent) } }
                                Text("\(stats.total) puzzles · \(stats.solved) solved\(stats.failed > 0 ? " · \(stats.failed) to review" : "")").font(.footnote).foregroundStyle(.secondary)
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
        }.navigationTitle("Puzzles")
            .fullScreenCover(item: $app.session) { SessionView(scope: $0.scope).environment(app) }
            .task { await openLaunchRoute() }
    }
    private func openLaunchRoute() async {
        #if DEBUG
        guard let route = app.launchRoute, let library = app.store.library else { return }
        if route == "collection", let first = library.collections.first { app.puzzlesPath = [.collection(first.id)] }
        if route.hasPrefix("session:") || route.hasPrefix("result:") {
            let scope = route == "session:missing" ? "sample-missing-piece" : SCOPE_ALL
            let puzzles = scope == SCOPE_ALL ? allPuzzles(library) : puzzlesIn(library, scope)
            await app.begin(scope, .ordered, puzzles.map(\.id))
        }
        #endif
    }
}
