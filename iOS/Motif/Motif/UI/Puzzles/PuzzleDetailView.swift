import SwiftUI
@Observable @MainActor final class PuzzleDetailModel {
    var puzzle: Puzzle
    var lineIndex = 0 { didSet { ply = 0 } }
    var ply = 0
    var comment: String
    init(_ puzzle: Puzzle) { self.puzzle = puzzle; comment = puzzle.comment ?? "" }
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
    @Environment(\.dismiss) private var dismiss
    let puzzle: Puzzle
    @State private var model: PuzzleDetailModel
    @State private var deleteConfirmation = false
    @State private var saving = false
    init(puzzle: Puzzle) { self.puzzle = puzzle; _model = State(initialValue: PuzzleDetailModel(puzzle)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BoardView(fen: model.fen, orientation: solverSide(puzzle), interactive: false, highlight: model.highlight)
                replay
                facts
                Text("Comment").font(.headline)
                TextEditor(text: $model.comment).frame(minHeight: 90).padding(8).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("edit-puzzle-comment")
                Button(saving ? "Saving…" : "Save comment") {
                    saving = true
                    let comment = model.comment
                    Task { _ = await app.edit({ try await $0.setComment(puzzle.id, comment) }, done: "Comment saved."); saving = false }
                }.disabled(!app.store.online || saving || model.comment.trimmingCharacters(in: .whitespacesAndNewlines) == (puzzle.comment ?? ""))
                Button(puzzle.flagged == true ? "Unflag puzzle" : "Flag for review") { Task { _ = await app.edit { try await $0.setFlagged(puzzle.id, puzzle.flagged != true) } } }.disabled(!app.store.online)
                Button("Delete puzzle", role: .destructive) { deleteConfirmation = true }.disabled(!app.store.online)
                OfflineNote()
            }.padding()
        }.navigationTitle(puzzle.sourceId.map { "#" + $0 } ?? "Puzzle").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively).editorKeyboard()
            .onChange(of: puzzle) { _, next in model.puzzle = next }
            .confirmationDialog("Delete this puzzle from the library?", isPresented: $deleteConfirmation, titleVisibility: .visible) {
                Button("Delete puzzle", role: .destructive) { Task { if await app.edit({ try await $0.deletePuzzle(puzzle.id) }) { dismiss() } } }
            }
    }
    @ViewBuilder private var replay: some View {
        if let answer = puzzle.addPiece { Text("\(answer.color == .white ? "White" : "Black") \(answer.type.name.lowercased()) on \(answer.square)") }
        else {
            if puzzle.solutions.count > 1 { Picker("Solution", selection: $model.lineIndex) { ForEach(puzzle.solutions.indices, id: \.self) { Text("Line \($0 + 1)").tag($0) } }.pickerStyle(.segmented) }
            HStack {
                Button { model.ply = 0 } label: { Image(systemName: "backward.end") }.disabled(model.ply == 0)
                Button { model.ply -= 1 } label: { Image(systemName: "chevron.left") }.disabled(model.ply == 0)
                ScrollView(.horizontal) {
                    HStack { ForEach(Array(model.steps.enumerated()), id: \.offset) { index, step in Button(step.san) { model.ply = index + 1 }.buttonStyle(.bordered).tint(model.ply == index + 1 ? .motifAccent : .secondary) } }
                }
                Button { model.ply += 1 } label: { Image(systemName: "chevron.right") }.disabled(model.ply >= model.steps.count)
            }
        }
    }
    private var facts: some View {
        VStack(alignment: .leading, spacing: 8) {
            let record = puzzleRecords(app.store.library?.attempts ?? [])[puzzle.id]
            Text(statusLabel(record?.status ?? .unseen) + (record.map { " · \($0.attempts) attempts, \($0.mistakes) mistakes" } ?? ""))
            if puzzle.flagged == true { Text("Flagged as possibly broken").foregroundStyle(.orange) }
            if !puzzle.tags.isEmpty { Text("Motif: " + puzzle.tags.joined(separator: " · ")) }
            if let rating = puzzle.rating { Text("Rating: \(rating.formatted())") }
            Text(puzzle.fen).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
