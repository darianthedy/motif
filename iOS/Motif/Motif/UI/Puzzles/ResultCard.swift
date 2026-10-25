import SwiftUI
struct ResultCard: View {
    let model: SolveModel
    let continueAction: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.verdict).font(.headline).foregroundStyle(model.phase == .solved ? Color.motifAccent : .red).accessibilityIdentifier("result-verdict")
            mistakes
            metadata
            solutions
            Button("Continue", action: continueAction).buttonStyle(.borderedProminent).frame(maxWidth: .infinity).accessibilityIdentifier("result-continue")
        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    @ViewBuilder private var mistakes: some View {
        if let missing = model.missing, !missing.wrongGuesses.isEmpty {
            let text = missing.wrongGuesses.map(placementText).joined(separator: " · ") + " → " + placementText(missing.answer)
            Text(text).foregroundStyle(.red)
        }
        ForEach(model.misses, id: \.ply) { miss in
            let text = ordinal(miss.ply) + "  " + miss.tried.joined(separator: " · ") + (miss.wanted.map { " → " + $0 } ?? "")
            Text(text).font(.subheadline)
        }
    }
    @ViewBuilder private var metadata: some View {
        if let comment = model.puzzle.comment, !comment.isEmpty { Text(comment).accessibilityIdentifier("puzzle-comment") }
        if !model.puzzle.tags.isEmpty { Text(model.puzzle.tags.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("puzzle-tags") }
        if let placement = model.puzzle.addPiece {
            let color = placement.color == .white ? "White" : "Black"
            Text("\(placementText(placement)) · \(color) \(placement.type.name.lowercased()) on \(placement.square)")
        }
    }
    private var solutions: some View {
        ForEach(Array(model.lines.enumerated()), id: \.offset) { n, line in
            HStack(alignment: .top) {
                if model.lines.count > 1 { Text("\(n + 1)").foregroundStyle(.secondary) }
                Text(line.steps.map(\.san).joined(separator: "  ")).font(.system(.body, design: .monospaced))
                if line.played { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.motifAccent).accessibilityLabel("Your line") }
            }
        }
    }
    private func ordinal(_ index: Int) -> String { let first = ["1st", "2nd", "3rd"]; return first.indices.contains(index) ? first[index] : "\(index + 1)th" }
}
