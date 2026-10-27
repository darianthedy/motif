import SwiftUI
struct CollectionView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let collectionId: String
    @State private var rename = false
    @State private var name = ""
    @State private var deletion = false
    @State private var importing = false
    var body: some View {
        Group {
            if let library = app.store.library, let collection = library.collections.first(where: { $0.id == collectionId }) {
                let puzzles = puzzlesIn(library, collectionId)
                ZStack {
                    if puzzles.isEmpty {
                        EmptyState(title: "No Puzzles", systemImage: "puzzlepiece",
                                   description: "Import puzzles into this collection to start solving.",
                                   action: .init(title: "Import Puzzles", identifier: "import-into-collection-empty", disabled: !app.store.online) { importing = true })
                    } else {
                        List {
                            Section { StatsCard(stats: statsFor(puzzles.map(\.id), puzzleRecords(library.attempts))) }
                            if let run = runIn(library, collectionId), let current = progressOf(library, run).current, !current.isEmpty {
                                session(remaining: progressOf(library, run).remaining, run: run)
                            }
                            Section("Solve") {
                                Button { Task { await app.begin(collectionId, .ordered, puzzles.map(\.id)) } } label: {
                                    Label("Solve in Order", systemImage: "list.number")
                                }.accessibilityIdentifier("solve-ordered")
                                Button { Task { await app.begin(collectionId, .randomInCollection, puzzles.map(\.id)) } } label: {
                                    Label("Solve Shuffled", systemImage: "shuffle")
                                }.accessibilityIdentifier("solve-shuffled")
                            }
                            Section {
                                NavigationLink(value: PuzzleRoute.puzzles(collectionId)) {
                                    LabeledContent { Text("\(puzzles.count)") } label: { Label("All Puzzles", systemImage: "square.grid.2x2") }
                                }.accessibilityIdentifier("browse-puzzles")
                            }
                        }
                    }
                }
                .navigationTitle(collection.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("More", systemImage: "ellipsis") {
                            Button("Rename…", systemImage: "pencil") { name = collection.name; rename = true }
                            Button("Import Into Collection…", systemImage: "square.and.arrow.down") { importing = true }
                            Divider()
                            Button("Delete Collection", systemImage: "trash", role: .destructive) { deletion = true }
                        }.disabled(!app.store.online).accessibilityIdentifier("collection-actions")
                    }
                }
            } else { Color.clear.onAppear { dismiss() } }
        }
            .alert("Rename the collection", isPresented: $rename) {
                TextField("Name", text: $name)
                Button("Save") {
                    let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chosen.isEmpty { Task { _ = await app.edit { try await $0.renameCollection(collectionId, chosen) } } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this collection and its puzzles?", isPresented: $deletion, titleVisibility: .visible) {
                Button("Delete Collection", role: .destructive) { Task { if await app.edit({ try await $0.deleteCollection(collectionId) }) { app.puzzlesPath = [] } } }
            }
            .sheet(isPresented: $importing) { ImportView(collectionId: collectionId).environment(app) }
    }
    private func session(remaining: Int, run: Run) -> some View {
        Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session in Progress").font(.headline)
                    Text("\(remaining) left").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Resume", systemImage: "play.fill") { app.session = SessionRoute(scope: collectionId) }
                    .buttonStyle(.glassProminent).buttonBorderShape(.capsule).accessibilityIdentifier("resume-session")
            }.padding(.vertical, 4)
            Button("Discard Session", role: .destructive) { Task { _ = await app.edit { try await $0.deleteRun(run.id) } } }
                .disabled(!app.store.online).accessibilityIdentifier("discard-session")
        }
    }
}
/// Solved / To review / New counts over one stacked bar.
private struct StatsCard: View {
    let stats: Stats
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                figure(stats.solved, "Solved", Color.motifAccentStrong)
                figure(stats.failed, "To Review", .orange)
                figure(stats.unseen, "New", .secondary)
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    segment(stats.solved, Color.motifAccent, geometry.size.width)
                    segment(stats.failed, .orange, geometry.size.width)
                    segment(stats.unseen, Color.secondary.opacity(0.3), geometry.size.width)
                }
            }
            .frame(height: 8).clipShape(.capsule)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
    private func figure(_ count: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)").font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func segment(_ count: Int, _ color: Color, _ width: CGFloat) -> some View {
        if count > 0, stats.total > 0 {
            let gaps = CGFloat([stats.solved, stats.failed, stats.unseen].filter { $0 > 0 }.count - 1) * 2
            color.frame(width: max(0, (width - gaps) * CGFloat(count) / CGFloat(stats.total)))
        }
    }
}
