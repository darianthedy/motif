import SwiftUI
/// The glass card shown once a puzzle is done, sized to its content (decision 15, F5).
/// The session places it: in the column beside the board on two panes, below the board
/// when stacked with room, rising from the bottom on compact width. Its details scroll
/// only when they outgrow the height the session proposes (62 % of the screen on compact).
struct ResultCard: View {
    /// On two panes and stacked regular layouts the card is at most this wide.
    static let maxWidth: CGFloat = 560
    let model: SolveModel
    /// Opens the puzzle's start position in the Analysis view.
    let analyze: () -> Void
    let continueAction: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var solved: Bool { model.phase == .solved }
    var body: some View {
        VStack(spacing: 16) {
            ViewThatFits(in: .vertical) {
                details
                ScrollView { details }.scrollBounceBehavior(.basedOnSize)
            }
            // Stacked at accessibility sizes, so neither title truncates beside the other (D10).
            let stacked = typeSize.isAccessibilitySize
            let buttons = stacked ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            buttons {
                Button(action: analyze) { Label("Analyze", systemImage: "magnifyingglass").font(.headline).frame(maxWidth: stacked ? .infinity : nil) }
                    .buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("result-analyze")
                Button(action: continueAction) { Text("Continue").font(.headline).frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("result-continue")
            }
        }
        .padding(20)
        .motifGlass(in: .rect(cornerRadius: 28))
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
            Text(text).font(.subheadline.monospacedDigit()).foregroundStyle(.motifSecondary)
        }
    }
    @ViewBuilder private var metadata: some View {
        if let placement = model.puzzle.addPiece {
            let color = placement.color == .white ? "White" : "Black"
            Text("\(placementText(placement)) · \(color) \(placement.type.name.lowercased()) on \(placement.square)").font(.subheadline)
        }
        if let comment = model.puzzle.comment, !comment.isEmpty { Text(comment).accessibilityIdentifier("puzzle-comment") }
        if !model.puzzle.tags.isEmpty {
            Text(model.puzzle.tags.map(motifLabel).joined(separator: " · ")).font(.footnote).foregroundStyle(.motifSecondary).accessibilityIdentifier("puzzle-tags")
        }
    }
    private var solutions: some View {
        ForEach(Array(model.lines.enumerated()), id: \.offset) { n, line in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if model.lines.count > 1 { Text("\(n + 1)").foregroundStyle(.motifSecondary) }
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
