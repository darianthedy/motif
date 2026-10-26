import SwiftUI
struct PuzzleListView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let collectionId: String
    @State private var filter = "all"
    var body: some View {
        Group {
            if let library = app.store.library, library.collections.contains(where: { $0.id == collectionId }) {
                let puzzles = puzzlesIn(library, collectionId), records = puzzleRecords(library.attempts)
                List {
                    Picker("Show", selection: $filter) {
                        Text("All").tag("all"); Text("New").tag("unseen"); Text("To review").tag("failed"); Text("Solved").tag("solved"); Text("Flagged").tag("flagged")
                    }
                    ForEach(Array(puzzles.enumerated()).filter { _, puzzle in
                        filter == "all" || (filter == "flagged" ? puzzle.flagged == true : statusOf(records, puzzle.id).rawValue == filter)
                    }, id: \.element.id) { index, puzzle in
                        NavigationLink(value: PuzzleRoute.puzzle(collectionId, puzzle.id)) {
                            HStack {
                                Text("\(index + 1)").foregroundStyle(.secondary)
                                Text(puzzle.sourceId.map { "#" + $0 } ?? "\(solverSide(puzzle) == .white ? "White" : "Black") \(puzzle.addPiece == nil ? "to play" : "piece missing")")
                                Spacer()
                                if puzzle.flagged == true { Image(systemName: "flag.fill").accessibilityLabel("Flagged") }
                                Text(statusLabel(statusOf(records, puzzle.id))).font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("puzzle-" + puzzle.id)
                    }
                }
            } else { Color.clear.onAppear { dismiss() } }
        }.navigationTitle("Puzzles")
    }
}
func statusLabel(_ status: PuzzleStatus) -> String { switch status { case .unseen: "New"; case .failed: "To review"; case .solved: "Solved" } }
