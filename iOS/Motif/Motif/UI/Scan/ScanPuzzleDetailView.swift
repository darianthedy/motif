import SwiftUI

/// One scan puzzle: the position the solver scans with the last move highlighted and the maker's
/// quick-scan squares and targets marked, then the answer and labels. Delete needs a connection.
struct ScanPuzzleDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    let puzzleId: String
    @State private var deleting = false
    @State private var container: CGSize = .zero
    @State private var division: CGRect?
    var body: some View {
        Group {
            if let library = app.store.library, let index = scanPool(library).firstIndex(where: { $0.id == puzzleId }) {
                let puzzle = scanPool(library)[index]
                content(puzzle, ScanPuzzleSummary(puzzle, index: index), scanRecords(library)[puzzle.id])
            } else { Color.clear.onAppear { dismiss() } }
        }.toolbar(.hidden, for: .tabBar)
    }
    private func content(_ puzzle: ScanPuzzle, _ summary: ScanPuzzleSummary, _ record: PuzzleRecord?) -> some View {
        let layout = BoardLayout(container: container, compact: sizeClass == .compact, evalBar: false, division: division)
        let stack = layout.sideBySide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: layout.spacing))
            : AnyLayout(VStackLayout(alignment: .center, spacing: layout.spacing))
        let padding = EdgeInsets(top: layout.padding.top, leading: layout.padding.leading,
                                 bottom: layout.padding.bottom - BoardLayout.inset, trailing: layout.padding.trailing)
        return stack {
            BoardView(fen: puzzle.startFen ?? puzzle.fenBefore, orientation: summary.solver, interactive: false,
                      highlight: (moveFrom(puzzle.lastMove), moveTo(puzzle.lastMove)),
                      mode: .markSquares, annotations: Self.annotations(puzzle.answer))
                .allowsHitTesting(false).frame(width: layout.board, height: layout.board)
                .accessibilitySortPriority(1)
            List {
                Section("Answer") {
                    LabeledContent("Last Move", value: summary.lastMove)
                    LabeledContent("Call", value: summary.call)
                    LabeledContent("Quick Scan", value: summary.quickScan)
                    if !summary.bestMoves.isEmpty { LabeledContent("Best Move", value: summary.bestMoves.joined(separator: ", ")) }
                    if let line = summary.bestLine { LabeledContent("Best Line", value: line) }
                }
                Section {
                    LabeledContent {
                        Text(statusLabel(record?.status ?? .unseen))
                    } label: {
                        Text("Status")
                        if let record { Text(countLabel(record.attempts, "attempt")) }
                    }
                    if let source = puzzle.content.source { LabeledContent("Source", value: source) }
                    if let id = puzzle.content.sourceId { LabeledContent("Source ID", value: id) }
                    LabeledContent("Format", value: "Version \(puzzle.content.version)")
                }
            }
            .listStyle(.insetGrouped).listSectionSpacing(.compact)
            .scrollContentBackground(.hidden).contentMargins(.top, 0, for: .scrollContent)
            .accessibilityIdentifier("scan-detail-list")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .motifOfferedSize($container)
        .motifDivision($division)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("#" + summary.number).navigationBarTitleDisplayMode(.inline)
        .motifOverflowMenu("Puzzle actions", identifier: "scan-puzzle-actions") {
            Button("Copy FEN", systemImage: "doc.on.doc") { UIPasteboard.general.string = puzzle.startFen ?? puzzle.fenBefore; app.showNotice("FEN copied.") }
            Section { Button("Delete Puzzle", systemImage: "trash", role: .destructive) { deleting = true }.disabled(!app.store.online) }
        }
        .confirmationDialog("Delete this scan puzzle?", isPresented: $deleting, titleVisibility: .visible) {
            // The view pops once the puzzle is gone from the library.
            Button("Delete Puzzle", role: .destructive) { Task { _ = await app.edit { try await $0.deleteScanPuzzle(puzzle.id) } } }
        } message: { Text("Its results are deleted with it.") }
    }
    /// The maker's answer as marks: quick-scan squares highlighted, targets red / orange / dots.
    static func annotations(_ answer: ScanAnswer) -> BoardAnnotations {
        var annotations = BoardAnnotations()
        for square in answer.quickScan { annotations.tints[square.square] = .quickScan }
        if let targets = answer.targets {
            for square in targets.red { annotations.tints[square] = .red }
            for square in targets.orange { annotations.tints[square] = .orange }
            // No king-zone dots: `kingZone` is always empty from v4.
            annotations.dots = Set(targets.fork)
        }
        annotations.arrows = (answer.arrows ?? []).map { BoardArrow(from: $0.from, to: $0.to, side: $0.side == .own ? .own : .theirs) }
        return annotations
    }
}
