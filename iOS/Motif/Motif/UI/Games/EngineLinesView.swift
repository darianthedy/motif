import SwiftUI

/// The engine's best lines for the position on the board, under it. Tapping a line
/// plays its first move.
struct EngineLinesView: View {
    let lines: [EngineLine]
    /// The position the lines start from.
    let fen: String
    let play: (Uci) -> Void
    /// A short column (O, SV, IP) packs the rows, as the canvas draws them, so the three
    /// lines fit where they replace the move list.
    var short = false

    static let count = 3
    /// Row and header heights grow with Dynamic Type, so nothing clips at AX5 (D10).
    @ScaledMetric(relativeTo: .subheadline) private var tallRow: CGFloat = 40
    @ScaledMetric(relativeTo: .subheadline) private var shortRow: CGFloat = 28
    @ScaledMetric(relativeTo: .caption) private var headHeight: CGFloat = 22
    private var rowHeight: CGFloat { short ? shortRow : tallRow }

    var body: some View {
        let rows = lines.compactMap { line in Self.text(line, from: fen).map { (line, $0) } }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Engine Lines").font(.caption.weight(.semibold)).foregroundStyle(.motifSecondary).textCase(.uppercase)
                Spacer()
                Text(lines.first.map { "Depth \($0.depth)" } ?? "Analysing…").font(.caption).monospacedDigit().foregroundStyle(.motifSecondary)
            }.padding(.horizontal, 12).frame(minHeight: headHeight)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let (line, text) = row
                Button { if let move = line.moves.first.flatMap(Uci.parse) { play(move) } } label: {
                    HStack(spacing: 10) {
                        Text(Self.score(line.score))
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Self.whiteAhead(line.score) ? EvalBar.blackPart : EvalBar.whitePart)
                            .frame(minWidth: 48, minHeight: 24)
                            .background(Self.whiteAhead(line.score) ? EvalBar.whitePart : EvalBar.blackPart, in: .rect(cornerRadius: 6))
                            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.separator), lineWidth: 0.5) }
                        Text("\(Text(text.first).fontWeight(.semibold)) \(Text(text.rest).foregroundStyle(.motifSecondary))")
                            .font(.subheadline).monospacedDigit().lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.horizontal, 12).frame(minHeight: rowHeight).contentShape(.rect)
                }.buttonStyle(.plain)
                    .accessibilityLabel("Line \(index + 1), \(Self.spoken(line.score)): \(text.first) \(text.rest)")
                    .accessibilityHint("Plays \(text.first)")
                    .accessibilityIdentifier("engine-line-\(index)")
            }
        }
        .padding(.vertical, 4)
        // Room for every line, so the move list doesn't jump while the lines come in.
        .frame(maxWidth: .infinity, minHeight: headHeight + 8 + rowHeight * CGFloat(Self.count), alignment: .top)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain).accessibilityLabel("Engine lines")
        .accessibilityIdentifier("engine-lines")
    }

    /// The line's first move and the rest of it, in SAN with move numbers, up to
    /// `limit` plies. Nil when its first move isn't legal here.
    static func text(_ line: EngineLine, from fen: String, limit: Int = 10) -> (first: String, rest: String)? {
        let steps = Board.replayLine(fen, line.moves.prefix(limit).compactMap(Uci.parse))
        guard !steps.isEmpty else { return nil }
        var before = fen, parts: [String] = []
        for (index, step) in steps.enumerated() {
            parts.append((moveNumber(before, index == 0).map { $0 + " " } ?? "") + step.san)
            before = step.fen
        }
        return (parts[0], parts.dropFirst().joined(separator: " "))
    }

    /// `+0.31` / `−1.20` / `+M3`, from White's point of view.
    static func score(_ score: Score) -> String {
        switch score {
        case .cp(let cp): return (cp < 0 ? "−" : "+") + String(format: "%.2f", Double(abs(cp)) / 100)
        case .mate(let moves): return (moves < 0 ? "−" : "+") + "M\(abs(moves))"
        }
    }

    static func whiteAhead(_ score: Score) -> Bool {
        switch score {
        case .cp(let cp): return cp >= 0
        case .mate(let moves): return moves > 0
        }
    }

    private static func spoken(_ score: Score) -> String {
        let side = whiteAhead(score) ? "White" : "Black"
        switch score {
        case .cp(let cp): return cp == 0 ? "equal" : "\(side) better by \(String(format: "%.2f", Double(abs(cp)) / 100))"
        case .mate(let moves): return "\(side) mates in \(abs(moves))"
        }
    }
}
