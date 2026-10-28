import SwiftUI
/// The glass sheet that rises over the lower half of the board once a puzzle
/// is done. Its details scroll only when they outgrow the space.
struct ResultCard: View {
    let model: SolveModel
    /// Opens the puzzle's start position in the Analysis view.
    let analyze: () -> Void
    let continueAction: () -> Void
    private var solved: Bool { model.phase == .solved }
    var body: some View {
        VStack(spacing: 16) {
            ViewThatFits(in: .vertical) {
                details
                ScrollView { details }.scrollBounceBehavior(.basedOnSize)
            }
            HStack(spacing: 10) {
                Button(action: analyze) { Label("Analyze", systemImage: "magnifyingglass").font(.headline) }
                    .buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("result-analyze")
                Button(action: continueAction) { Text("Continue").font(.headline).frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("result-continue")
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(.horizontal, 8)
        .containerRelativeFrame(.vertical, alignment: .bottom) { height, _ in height * 0.62 }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: solved ? "checkmark.circle.fill" : "xmark.circle.fill").font(.title2)
                    .foregroundStyle(solved ? Color.motifAccent : .red).accessibilityHidden(true)
                Text(model.verdict).font(.headline).foregroundStyle(solved ? Color.motifAccentStrong : .red).accessibilityIdentifier("result-verdict")
            }
            mistakes
            solutions
            metadata
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var mistakes: some View {
        if let missing = model.missing, !missing.wrongGuesses.isEmpty {
            let text = missing.wrongGuesses.map(placementText).joined(separator: " · ") + " → " + placementText(missing.answer)
            Text(text).font(.subheadline).foregroundStyle(.red)
        }
        ForEach(model.misses, id: \.ply) { miss in
            let text = ordinal(miss.ply) + "  " + miss.tried.joined(separator: " · ") + (miss.wanted.map { " → " + $0 } ?? "")
            Text(text).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var metadata: some View {
        if let placement = model.puzzle.addPiece {
            let color = placement.color == .white ? "White" : "Black"
            Text("\(placementText(placement)) · \(color) \(placement.type.name.lowercased()) on \(placement.square)").font(.subheadline)
        }
        if let comment = model.puzzle.comment, !comment.isEmpty { Text(comment).accessibilityIdentifier("puzzle-comment") }
        if !model.puzzle.tags.isEmpty {
            Text(model.puzzle.tags.map(motifLabel).joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("puzzle-tags")
        }
    }
    private var solutions: some View {
        ForEach(Array(model.lines.enumerated()), id: \.offset) { n, line in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if model.lines.count > 1 { Text("\(n + 1)").foregroundStyle(.secondary) }
                Text(line.steps.map(\.san).joined(separator: "  ")).font(.system(.body, design: .monospaced))
                if line.played {
                    Text("Your line").font(.caption.weight(.semibold)).foregroundStyle(Color.motifAccentStrong)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Color.motifAccent.opacity(0.2), in: .capsule)
                }
            }
        }
    }
    private func ordinal(_ index: Int) -> String { let first = ["1st", "2nd", "3rd"]; return first.indices.contains(index) ? first[index] : "\(index + 1)th" }
}
