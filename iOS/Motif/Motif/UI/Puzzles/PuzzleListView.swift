import SwiftUI
enum PuzzleScope: String, CaseIterable, Hashable {
    case all, new, review, solved, flagged
    var title: String { switch self { case .all: "All"; case .new: "New"; case .review: "Review"; case .solved: "Solved"; case .flagged: "Flagged" } }
    func includes(_ puzzle: Puzzle, _ status: PuzzleStatus) -> Bool {
        switch self {
        case .all: true
        case .new: status == .unseen
        case .review: status == .failed
        case .solved: status == .solved
        case .flagged: puzzle.flagged == true
        }
    }
}
struct PuzzleListItem: Identifiable, Equatable {
    /// `#sourceId`, or the puzzle's place in the collection when it has none.
    let number: String
    let puzzle: Puzzle
    let status: PuzzleStatus
    var id: String { puzzle.id }
}
@Observable @MainActor final class PuzzleListModel {
    var query = ""
    var scope = PuzzleScope.all
    /// The scope's puzzles whose number or a motif tag contains the query.
    func items(_ puzzles: [Puzzle], _ records: [String: PuzzleRecord]) -> [PuzzleListItem] {
        let needle = searchKey(query)
        return puzzles.enumerated().compactMap { index, puzzle in
            let item = PuzzleListItem(number: puzzle.sourceId ?? "\(index + 1)", puzzle: puzzle, status: statusOf(records, puzzle.id))
            guard scope.includes(puzzle, item.status) else { return nil }
            guard needle.isEmpty || searchKey(item.number).contains(needle) || puzzle.tags.contains(where: { searchKey($0).contains(needle) }) else { return nil }
            return item
        }
    }
    /// Case, spacing and a leading `#` don't matter: "back rank" finds `backRank`, "#412" finds `00412`.
    private func searchKey(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && $0 != "#" && $0 != "-" && $0 != "_" }
    }
}
/// "mateIn2" → "Mate in 2", "backRank" → "back rank".
func motifLabel(_ tag: String) -> String {
    var words = ""
    for character in tag {
        if character.isUppercase || (character.isNumber && !(words.last?.isNumber ?? true)) { words += " " }
        words += character.lowercased()
    }
    words = words.trimmingCharacters(in: .whitespaces)
    return words.hasPrefix("mate in ") ? "M" + String(words.dropFirst()) : words
}
struct PuzzleListView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let collectionId: String
    @State private var model = PuzzleListModel()
    @State private var deleting: Puzzle?
    var body: some View {
        @Bindable var model = model
        Group {
            if let library = app.store.library, let collection = library.collections.first(where: { $0.id == collectionId }) {
                let puzzles = puzzlesIn(library, collectionId), items = model.items(puzzles, puzzleRecords(library.attempts))
                List {
                    ForEach(items) { item in
                        NavigationLink(value: PuzzleRoute.puzzle(collectionId, item.puzzle.id)) { PuzzleRow(item: item) }
                            .accessibilityIdentifier("puzzle-" + item.puzzle.id)
                            .swipeActions {
                                Button("Delete", systemImage: "trash") { deleting = item.puzzle }.tint(.red).disabled(!app.store.online)
                                Button(item.puzzle.flagged == true ? "Unflag" : "Flag", systemImage: item.puzzle.flagged == true ? "flag.slash" : "flag") {
                                    Task { _ = await app.edit { try await $0.setFlagged(item.puzzle.id, item.puzzle.flagged != true) } }
                                }.tint(.orange).disabled(!app.store.online)
                            }
                    }
                }
                .overlay { if items.isEmpty { empty(puzzles.isEmpty) } }
                .navigationSubtitle(collection.name)
            } else { Color.clear.onAppear { dismiss() } }
        }
        .navigationTitle("All Puzzles")
        .searchable(text: $model.query, prompt: "Number or motif")
        .searchScopes($model.scope) { ForEach(PuzzleScope.allCases, id: \.self) { Text($0.title).tag($0) } }
        .task {
            #if DEBUG
            // The samples have no flagged puzzles, so this scope shows the empty state.
            if app.launchRoute == "puzzle-list-empty" { model.scope = .flagged }
            #endif
        }
        .confirmationDialog("Delete this puzzle from the library?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { puzzle in
            Button("Delete Puzzle", role: .destructive) { Task { _ = await app.edit { try await $0.deletePuzzle(puzzle.id) } } }
        }
    }
    @ViewBuilder private func empty(_ noPuzzles: Bool) -> some View {
        if noPuzzles { EmptyState(title: "No Puzzles", systemImage: "puzzlepiece") }
        else if !model.query.trimmingCharacters(in: .whitespaces).isEmpty { ContentUnavailableView.search(text: model.query) }
        else {
            let label = model.scope == .review ? "Puzzles to Review" : "\(model.scope.title) Puzzles"
            EmptyState(title: "No \(label)", systemImage: model.scope == .flagged ? "flag" : "line.3.horizontal.decrease.circle")
        }
    }
}
private struct PuzzleRow: View {
    let item: PuzzleListItem
    var body: some View {
        HStack(spacing: 12) {
            BoardView(fen: item.puzzle.fen, orientation: solverSide(item.puzzle), interactive: false, coordinates: false)
                .frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 4))
                .allowsHitTesting(false).accessibilityHidden(true)
            RowStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("#" + item.number).font(.body.weight(.medium).monospacedDigit())
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).rowLineLimit()
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    if item.puzzle.flagged == true {
                        Image(systemName: "flag.fill").foregroundStyle(.orange).accessibilityLabel("Flagged")
                    }
                    status
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
    private var subtitle: String {
        let puzzle = item.puzzle
        var parts = puzzle.tags.map(motifLabel)
        if parts.isEmpty { parts.append("\(solverSide(puzzle) == .white ? "White" : "Black") \(puzzle.addPiece == nil ? "to play" : "piece missing")") }
        if let rating = puzzle.rating { parts.append("\(Int(rating.rounded()))") }
        return parts.joined(separator: " · ")
    }
    private var status: some View {
        let (symbol, color): (String, Color) = switch item.status {
        case .unseen: ("circle", .secondary)
        case .failed: ("arrow.counterclockwise.circle.fill", .orange)
        case .solved: ("checkmark.circle.fill", .motifAccentStrong)
        }
        return Label(statusLabel(item.status), systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(color)
            .labelStyle(StatusLabelStyle())
    }
}
private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title }
    }
}
func statusLabel(_ status: PuzzleStatus) -> String { switch status { case .unseen: "New"; case .failed: "To review"; case .solved: "Solved" } }
