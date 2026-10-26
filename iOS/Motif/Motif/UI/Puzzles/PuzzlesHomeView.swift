import SwiftUI

enum PuzzleRoute: Hashable { case collection(String), puzzles(String), puzzle(String, String) }
struct PuzzlesHomeView: View {
    @Environment(AppState.self) private var app
    @State private var renaming: Collection?
    @State private var name = ""
    @State private var deleting: Collection?
    var body: some View {
        @Bindable var app = app
        // One container for both states so the launch route, sheet and cover
        // aren't re-attached (and re-run or dismissed) when the first import lands.
        ZStack {
            if let library = app.store.library, !library.collections.isEmpty {
                List {
                    if !library.puzzles.isEmpty { practice(library) }
                    collections(library)
                }
            } else {
                EmptyState(title: "No Puzzles Yet", systemImage: "puzzlepiece",
                           description: "Import a JSON collection to start solving.",
                           action: .init(title: "Import Puzzles", identifier: "import-puzzles-empty", disabled: !app.store.online) { app.importingPuzzles = true })
            }
        }
        .navigationTitle("Puzzles")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import Puzzles", systemImage: "plus") { app.importingPuzzles = true }
                    .disabled(!app.store.online).accessibilityIdentifier("import-puzzles")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) { AccountButton() }
        }
        .alert("Rename the collection", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { collection in
            TextField("Name", text: $name)
            Button("Save") {
                let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !chosen.isEmpty { Task { _ = await app.edit { try await $0.renameCollection(collection.id, chosen) } } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this collection and its puzzles?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { collection in
            Button("Delete Collection", role: .destructive) { Task { _ = await app.edit { try await $0.deleteCollection(collection.id) } } }
        }
        .sheet(isPresented: $app.importingPuzzles) { ImportView().environment(app) }
        .fullScreenCover(item: $app.session) { SessionView(scope: $0.scope).environment(app) }
        .task { await openLaunchRoute() }
    }
    private var subtitle: String {
        guard let library = app.store.library, !library.collections.isEmpty else { return "" }
        return "\(countLabel(library.puzzles.count, "puzzle")) in \(countLabel(library.collections.count, "collection"))"
    }
    private func practice(_ library: Library) -> some View {
        let review = reviewIds(allPuzzles(library).map(\.id), puzzleRecords(library.attempts))
        return Section("Practice") {
            if let run = runIn(library, SCOPE_ALL), resumable(library, SCOPE_ALL) {
                Button { app.session = SessionRoute(scope: SCOPE_ALL) } label: {
                    PracticeRow(title: "Resume Random Session", systemImage: "play.fill", tile: .motifAccentStrong) {
                        Text("\(progressOf(library, run).remaining) left").foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("resume-random")
            }
            Button {
                Task { await app.begin(SCOPE_ALL, .randomGlobal, orderForGlobalDraw(allPuzzles(library).map(\.id), recentIds(library.attempts))) }
            } label: {
                PracticeRow(title: "Random From Everything", systemImage: "shuffle", tile: .blue) { EmptyView() }
            }.accessibilityIdentifier("solve-all")
            Button { Task { await app.begin(SCOPE_REVIEW, .reviewMistakes, review) } } label: {
                PracticeRow(title: "Review Mistakes", systemImage: "arrow.counterclockwise", tile: .orange) {
                    if !review.isEmpty {
                        Text("\(review.count)").font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 2).background(.orange, in: .capsule)
                    }
                }
            }.disabled(review.isEmpty).accessibilityIdentifier("review-mistakes")
        }
    }
    private func collections(_ library: Library) -> some View {
        let records = puzzleRecords(library.attempts)
        return Section("Collections") {
            ForEach(collectionsOf(library), id: \.id) { collection in
                let stats = statsFor(puzzlesIn(library, collection.id).map(\.id), records)
                NavigationLink(value: PuzzleRoute.collection(collection.id)) {
                    CollectionRow(name: collection.name, stats: stats, inProgress: resumable(library, collection.id))
                }
                .accessibilityIdentifier("collection-" + collection.id)
                .swipeActions {
                    Button("Delete", systemImage: "trash") { deleting = collection }.tint(.red).disabled(!app.store.online)
                }
                .contextMenu {
                    Button("Rename…", systemImage: "pencil") { name = collection.name; renaming = collection }.disabled(!app.store.online)
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = collection }.disabled(!app.store.online)
                }
            }
        }
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
/// A Settings-style row: coloured icon tile, title, trailing detail.
private struct PracticeRow<Trailing: View>: View {
    let title: String
    let systemImage: String
    let tile: Color
    @ViewBuilder let trailing: Trailing
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(tile.opacity(enabled ? 1 : 0.4), in: .rect(cornerRadius: 7))
                .accessibilityHidden(true)
            Text(title).foregroundStyle(enabled ? Color.primary : Color.secondary)
            Spacer()
            trailing
        }
    }
}
private struct CollectionRow: View {
    let name: String
    let stats: Stats
    let inProgress: Bool
    var body: some View {
        HStack(spacing: 12) {
            ProgressRing(fraction: stats.total > 0 ? Double(stats.solved) / Double(stats.total) : 0)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name).font(.body.weight(.medium))
                    if inProgress {
                        Text("In progress").font(.caption2.weight(.semibold)).foregroundStyle(Color.motifAccentStrong)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.motifAccent.opacity(0.18), in: .capsule)
                    }
                }
                Text("\(countLabel(stats.total, "puzzle")) · \(stats.solved) solved\(stats.failed > 0 ? " · \(stats.failed) to review" : "")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
private struct ProgressRing: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.motifAccent.opacity(0.2), lineWidth: 4)
            Circle().trim(from: 0, to: fraction).stroke(Color.motifAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(Int((fraction * 100).rounded()))%").font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(width: 36, height: 36)
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent solved")
    }
}
