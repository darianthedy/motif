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
    let puzzle: Puzzle
    @State private var model: PuzzleDetailModel
    @State private var deleteConfirmation = false
    @State private var commenting = false
    init(puzzle: Puzzle) { self.puzzle = puzzle; _model = State(initialValue: PuzzleDetailModel(puzzle)) }
    private var flagged: Bool { puzzle.flagged == true }
    private var title: String { "#" + (puzzle.sourceId ?? "\(puzzle.position + 1)") }
    var body: some View {
        List {
            Section {
                BoardView(fen: model.fen, orientation: solverSide(puzzle), interactive: false, highlight: model.highlight)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }.listSectionMargins(.horizontal, 0)
            if puzzle.addPiece == nil { solution }
            info
        }
        .listSectionSpacing(.compact)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(app.store.library?.collections.first(where: { $0.id == puzzle.collectionId })?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(flagged ? "Unflag" : "Flag", systemImage: flagged ? "flag.fill" : "flag") {
                    Task { _ = await app.edit { try await $0.setFlagged(puzzle.id, !flagged) } }
                }.tint(flagged ? .orange : nil).disabled(!app.store.online).accessibilityIdentifier("puzzle-flag")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Copy FEN", systemImage: "doc.on.doc") { UIPasteboard.general.string = puzzle.fen; app.showNotice("FEN copied.") }
                    Section { Button("Delete Puzzle", systemImage: "trash", role: .destructive) { deleteConfirmation = true }.disabled(!app.store.online) }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Puzzle actions").accessibilityIdentifier("puzzle-actions")
            }
            if puzzle.addPiece == nil {
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItemGroup(placement: .bottomBar) {
                    control("Go to start", "backward.end.fill", disabled: model.ply == 0) { model.ply = 0 }
                    control("Previous move", "chevron.left", disabled: model.ply == 0, action: model.back)
                    control("Next move", "chevron.right", disabled: model.ply >= model.steps.count, action: model.next)
                    control("Go to end", "forward.end.fill", disabled: model.ply >= model.steps.count, action: model.end)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
            }
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
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.chips.enumerated()), id: \.offset) { index, chip in
                            let selected = model.ply == index + 1
                            Button { model.ply = index + 1 } label: {
                                Text(chip).font(.subheadline.weight(selected ? .semibold : .regular).monospacedDigit())
                                    .foregroundStyle(selected ? Color.white : Color.primary).padding(.horizontal, 14).frame(height: 36)
                            }.buttonStyle(.plain)
                                .glassEffect(selected ? .regular.tint(.motifAccentStrong).interactive() : .regular.interactive(), in: .capsule)
                                .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("puzzle-move-\(index)").id(index)
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 4)
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
                        if let comment = puzzle.comment, !comment.isEmpty { Text(comment).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                        else { Text("Add Comment").font(.subheadline).foregroundStyle(.tint) }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }.contentShape(.rect)
            }.buttonStyle(.plain).disabled(!app.store.online).accessibilityIdentifier("puzzle-detail-comment")
        }
    }
    private func control(_ label: String, _ image: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(label, systemImage: image).font(.title3).imageScale(.large).frame(minWidth: 40, minHeight: 40) }
            .disabled(disabled).accessibilityIdentifier("puzzle-" + label.lowercased().replacingOccurrences(of: " ", with: "-"))
    }
}
