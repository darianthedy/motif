import SwiftUI
@Observable @MainActor final class PuzzleDetailModel {
    var puzzle: Puzzle
    var lineIndex = 0 { didSet { ply = 0 } }
    var ply = 0
    init(_ puzzle: Puzzle) { self.puzzle = puzzle }
    var steps: [Board.ReplayStep] { Board.replayLine(puzzle.fen, puzzle.solutions.indices.contains(lineIndex) ? puzzle.solutions[lineIndex] : []) }
    var fen: String {
        if let answer = puzzle.addPiece { return Board.withPiece(puzzle.fen, answer) ?? puzzle.fen }
        return ply > 0 && steps.indices.contains(ply - 1) ? steps[ply - 1].fen : puzzle.fen
    }
    var highlight: (from: String, to: String)? {
        if let answer = puzzle.addPiece { return (answer.square, answer.square) }
        guard ply > 0, steps.indices.contains(ply - 1) else { return nil }
        let move = steps[ply - 1].move; return (moveFrom(move), moveTo(move))
    }
    /// "1. Qe7", "1... Kh8": every chip is numbered so a line reads on its own.
    var chips: [String] {
        steps.enumerated().map { index, step in
            let before = index == 0 ? puzzle.fen : steps[index - 1].fen
            return [moveNumber(before, index == 0), step.san].compactMap { $0 }.joined(separator: " ")
        }
    }
    func back() { ply = max(ply - 1, 0) }
    func next() { ply = min(ply + 1, steps.count) }
    func end() { ply = steps.count }
}
struct PuzzleDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let puzzleId: String
    var body: some View {
        Group {
            if let puzzle = app.store.library?.puzzles.first(where: { $0.id == puzzleId }) { PuzzleDetailContent(puzzle: puzzle) }
            else { Color.clear.onAppear { dismiss() } }
        }.toolbar(.hidden, for: .tabBar)
    }
}
private struct PuzzleDetailContent: View {
    @Environment(AppState.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    let puzzle: Puzzle
    @State private var model: PuzzleDetailModel
    @State private var deleteConfirmation = false
    @State private var commenting = false
    /// The content's size inside the safe area and the bars, for `BoardLayout`.
    @State private var container: CGSize = .zero
    /// The fold's active division in the same coordinates, nil when flat (D07).
    @State private var division: CGRect?
    init(puzzle: Puzzle) { self.puzzle = puzzle; _model = State(initialValue: PuzzleDetailModel(puzzle)) }
    private var flagged: Bool { puzzle.flagged == true }
    private var title: String { "#" + (puzzle.sourceId ?? "\(puzzle.position + 1)") }
    var body: some View {
        // The board is pinned outside the list, which scrolls in the column beside it or below
        // it (decision 18, F1, F11). `AnyLayout` switches between the two, so a fold keeps the
        // step, the line and the sheets.
        // On a fold the board takes the leading page or the top half (D07).
        let layout = BoardLayout(container: container, compact: sizeClass == .compact, evalBar: false, division: division)
        let stack = layout.sideBySide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: layout.spacing))
            : AnyLayout(VStackLayout(alignment: .center, spacing: layout.spacing))
        // The list scrolls to the bottom edge, so no inset under it.
        let padding = EdgeInsets(top: layout.padding.top, leading: layout.padding.leading,
                                 bottom: layout.padding.bottom - BoardLayout.inset, trailing: layout.padding.trailing)
        stack {
            // Display-only: the detail replays, it doesn't take moves.
            BoardView(fen: model.fen, orientation: solverSide(puzzle), interactive: false, highlight: model.highlight)
                .allowsHitTesting(false).frame(width: layout.board, height: layout.board)
                .accessibilitySortPriority(1)
            List {
                if puzzle.addPiece == nil { solution }
                info
            }
            .listStyle(.insetGrouped).listSectionSpacing(.compact)
            .scrollContentBackground(.hidden).contentMargins(.top, 0, for: .scrollContent)
            .accessibilityIdentifier("puzzle-detail-list")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // VoiceOver: the board, then the solution and details, then the bar items (§6.14, D10).
        .accessibilityElement(children: .contain)
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { container = $0 }
        .motifDivision($division)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(app.store.library?.collections.first(where: { $0.id == puzzle.collectionId })?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(flagged ? "Unflag" : "Flag", systemImage: flagged ? "flag.fill" : "flag") {
                    Task { _ = await app.edit { try await $0.setFlagged(puzzle.id, !flagged) } }
                }.tint(flagged ? .orange : nil).disabled(!app.store.online).accessibilityIdentifier("puzzle-flag")
            }
            // The replay steps, as the Analysis view's bottom bar group (decision 13): the side bar
            // on the Duo, the bottom bar on an iPhone.
            if puzzle.addPiece == nil {
                ToolbarItemGroup(placement: .bottomBar) {
                    control("Go to Start", "backward.end.fill", disabled: model.ply == 0) { model.ply = 0 }
                    control("Previous Move", "chevron.left", disabled: model.ply == 0, action: model.back)
                    control("Next Move", "chevron.right", disabled: model.ply >= model.steps.count, action: model.next)
                    control("Go to End", "forward.end.fill", disabled: model.ply >= model.steps.count, action: model.end)
                }
            }
        }
        // Copy FEN and Delete Puzzle (F16); Delete only sets the flag the dialog below reads (F15).
        .motifOverflowMenu("Puzzle actions", identifier: "puzzle-actions") {
            Button("Copy FEN", systemImage: "doc.on.doc") { UIPasteboard.general.string = puzzle.fen; app.showNotice("FEN copied.") }
            Section { Button("Delete Puzzle", systemImage: "trash", role: .destructive) { deleteConfirmation = true }.disabled(!app.store.online) }
        }
        .sheet(isPresented: $commenting) {
            CommentSheet(title: title, value: puzzle.comment, online: app.store.online,
                         textIdentifier: "edit-puzzle-comment", saveIdentifier: "puzzle-comment-save") { text in
                let comment = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard comment != (puzzle.comment ?? "") else { return }
                Task { _ = await app.edit({ try await $0.setComment(puzzle.id, comment) }, done: comment.isEmpty ? "Comment removed." : "Comment saved.") }
            }
        }
        .confirmationDialog("Delete this puzzle from the library?", isPresented: $deleteConfirmation, titleVisibility: .visible) {
            // PuzzleDetailView pops once the puzzle is gone from the library.
            Button("Delete Puzzle", role: .destructive) { Task { _ = await app.edit { try await $0.deletePuzzle(puzzle.id) } } }
        }
        .sensoryFeedback(.selection, trigger: model.ply)
        .onChange(of: puzzle) { _, next in model.puzzle = next }
        .focusable().focusEffectDisabled()
        .onKeyPress(.leftArrow) { model.back(); return .handled }
        .onKeyPress(.rightArrow) { model.next(); return .handled }
    }
    /// Line picker (when there are several) above the line's moves as chips.
    @ViewBuilder private var solution: some View {
        Section {
            if puzzle.solutions.count > 1 {
                Picker("Solution", selection: $model.lineIndex) { ForEach(puzzle.solutions.indices, id: \.self) { Text("Line \($0 + 1)").tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("puzzle-line")
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.chips.enumerated()), id: \.offset) { index, chip in
                            let selected = model.ply == index + 1
                            Button { model.ply = index + 1 } label: {
                                Text(chip).font(.subheadline.weight(selected ? .semibold : .regular).monospacedDigit())
                                    .foregroundStyle(selected ? Color.white : Color.primary).padding(.horizontal, 14).frame(minHeight: 44)
                            }.buttonStyle(.plain)
                                .motifGlass(tint: selected ? .motifAccentStrong : nil, interactive: true, in: .capsule)
                                .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("puzzle-move-\(index)").id(index)
                        }
                    }.padding(.vertical, 4)
                }.scrollIndicators(.hidden)
                    .onChange(of: model.ply) { _, ply in withAnimation { proxy.scrollTo(max(ply - 1, 0)) } }
            }
            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        }.listSectionMargins(.horizontal, 0)
    }
    private var info: some View {
        Section {
            if let answer = puzzle.addPiece {
                LabeledContent("Answer", value: "\(answer.color == .white ? "White" : "Black") \(answer.type.name.lowercased()) on \(answer.square)")
            }
            let record = puzzleRecords(app.store.library?.attempts ?? [])[puzzle.id]
            LabeledContent {
                Text(statusLabel(record?.status ?? .unseen))
            } label: {
                Text("Status")
                if let record { Text(countLabel(record.attempts, "attempt") + " · " + countLabel(record.mistakes, "mistake")) }
            }
            if !puzzle.tags.isEmpty { LabeledContent("Motif", value: puzzle.tags.map(motifLabel).joined(separator: ", ")) }
            if let rating = puzzle.rating { LabeledContent("Rating", value: "\(Int(rating.rounded()))") }
            Button { commenting = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Comment").foregroundStyle(Color.primary)
                        if let comment = puzzle.comment, !comment.isEmpty { Text(comment).font(.subheadline).foregroundStyle(.motifSecondary).lineLimit(3) }
                        else { Text("Add Comment").font(.subheadline).foregroundStyle(.tint) }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                }.contentShape(.rect)
            }.buttonStyle(.plain).disabled(!app.store.online).accessibilityIdentifier("puzzle-detail-comment")
        }.listSectionMargins(.horizontal, 0)
    }
    private func control(_ label: String, _ image: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(label, systemImage: image, action: action)
            .disabled(disabled).accessibilityIdentifier("puzzle-" + label.lowercased().replacingOccurrences(of: " ", with: "-"))
    }
}
