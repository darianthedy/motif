import SwiftUI

/// Every puzzle in the pool, in the order it arrived, with its status. Swipe to delete.
struct ScanPuzzleListView: View {
    @Environment(AppState.self) private var app
    @State private var deleting: String?
    var body: some View {
        Group {
            if let library = app.store.library {
                let records = scanRecords(library)
                List {
                    ForEach(Array(scanPool(library).enumerated()), id: \.element.id) { index, puzzle in
                        NavigationLink(value: ScanRoute.puzzle(puzzle.id)) {
                            ScanPuzzleRow(puzzle: puzzle, summary: ScanPuzzleSummary(puzzle, index: index), status: statusOf(records, puzzle.id))
                        }
                        .accessibilityIdentifier("scan-puzzle-" + puzzle.id)
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash") { deleting = puzzle.id }.tint(.red).disabled(!app.store.online)
                        }
                        .confirmationDialog("Delete this scan puzzle?", isPresented: Binding(get: { deleting == puzzle.id }, set: { if !$0 { deleting = nil } }),
                                            titleVisibility: .visible) {
                            Button("Delete Puzzle", role: .destructive) { Task { _ = await app.edit { try await $0.deleteScanPuzzle(puzzle.id) } } }
                        } message: { Text("Its results are deleted with it.") }
                    }
                }
                .overlay { if library.scanPuzzles.isEmpty { EmptyState(title: "No Scan Puzzles", systemImage: "scope").readableWidth() } }
            }
        }
        .navigationTitle("All Puzzles")
    }
}
private struct ScanPuzzleRow: View {
    let puzzle: ScanPuzzle
    let summary: ScanPuzzleSummary
    let status: PuzzleStatus
    var body: some View {
        HStack(spacing: 12) {
            BoardView(fen: puzzle.startFen ?? puzzle.fenBefore, orientation: summary.solver, interactive: false, coordinates: false)
                .frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 4))
                .allowsHitTesting(false).accessibilityHidden(true)
            RowStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("#" + summary.number).font(.body.weight(.medium).monospacedDigit())
                    Text(subtitle).font(.footnote).foregroundStyle(.motifSecondary).rowLineLimit()
                }.frame(maxWidth: .infinity, alignment: .leading)
                statusBadge
            }
        }
        .accessibilityElement(children: .combine)
    }
    private var subtitle: String {
        ["After \(summary.lastMove)", puzzle.content.source].compactMap { $0 }.joined(separator: " · ")
    }
    private var statusBadge: some View {
        let (symbol, color): (String, Color) = switch status {
        case .unseen: ("circle", .motifSecondaryText)
        case .failed: ("arrow.counterclockwise.circle.fill", .orange)
        case .solved: ("checkmark.circle.fill", .motifAccentStrong)
        }
        return Label(statusLabel(status), systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(color)
    }
}
