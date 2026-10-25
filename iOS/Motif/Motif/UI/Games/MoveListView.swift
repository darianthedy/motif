import SwiftUI
struct MoveListView: View {
    let game: ParsedGame
    let path: MovePath
    let go: (MovePath) -> Void
    let hold: (MovePath) -> Void
    @State private var folded: [String: Bool] = [:]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(moveTable(game).enumerated()), id: \.offset) { _, item in
                        switch item {
                        case .row(let number, let white, let black):
                            HStack(spacing: 8) {
                                Text(number.formatted(.number.precision(.fractionLength(0))) + ".").font(.caption).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                                if let white { moveButton(white, number: nil).frame(maxWidth: .infinity, alignment: .leading) } else { Text("…").frame(maxWidth: .infinity, alignment: .leading) }
                                if let black { moveButton(black, number: nil).frame(maxWidth: .infinity, alignment: .leading) } else { Color.clear.frame(maxWidth: .infinity).frame(height: 1) }
                            }.padding(.vertical, 2)
                        case .variations(let fen, let alternatives):
                            ForEach(alternatives, id: \.path) { cell in variation(cell, fen: fen, depth: 0) }
                        }
                    }
                    if game.moves.isEmpty { Text("No moves yet. Play one on the board.").font(.footnote).foregroundStyle(.secondary).padding() }
                }.padding(.horizontal, 12)
            }.accessibilityIdentifier("game-move-list")
                .onChange(of: path) { _, next in withAnimation { proxy.scrollTo(moveID(next), anchor: .center) } }
        }
    }
    private func moveButton(_ cell: Cell, number: String?) -> some View {
        let text = (number.map { $0 + " " } ?? "") + cell.node.san + cell.node.nags.compactMap { NAG_SYMBOLS[$0] }.joined()
        return Button { go(cell.path) } label: {
            HStack(spacing: 4) {
                Text(text).font(.system(.subheadline, design: .monospaced))
                if !displayComment(cell.node.comment).isEmpty || !displayComment(cell.node.before).isEmpty { Image(systemName: "text.bubble.fill").font(.caption2).accessibilityLabel("Has a comment") }
            }.padding(.horizontal, 8).padding(.vertical, 6).background(cell.path == path ? Color.motifAccent.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).id(moveID(cell.path)).accessibilityIdentifier(moveID(cell.path))
            .accessibilityAddTraits(cell.path == path ? .isSelected : [])
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in hold(cell.path) })
    }
    private func variation(_ first: Cell, fen: String, depth: Int) -> AnyView {
        let id = moveID(first.path), length = lineLength(first.node)
        let open = folded[id].map { !$0 } ?? (length <= 6 || startsWith(path, first.path))
        var segments: [VariationSegment] = [], cells: [(Cell, String?)] = []
        var siblings = [first.node], before = fen, at = first.path, count = 0
        while let current = siblings.first, open || count < 5 {
            cells.append((Cell(node: current, path: at), moveNumber(before, cells.isEmpty)))
            if open, siblings.count > 1 {
                // Alternatives follow the move they replace, before its reply.
                let parent = Array(at.dropLast())
                let branches = siblings.dropFirst().enumerated().map {
                    (Cell(node: $0.element, path: parent + [$0.offset + 1]), before)
                }
                segments.append(VariationSegment(cells: cells, branches: branches)); cells = []
            }
            before = current.fen; siblings = current.children; at += [0]; count += 1
        }
        if !cells.isEmpty { segments.append(VariationSegment(cells: cells, branches: [])) }
        return AnyView(VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                FlowLayout(spacing: 2) { ForEach(segment.cells, id: \.0.path) { cell, number in moveButton(cell, number: number) } }
                ForEach(segment.branches, id: \.0.path) { cell, position in variation(cell, fen: position, depth: depth + 1) }
            }
            if length > 6 { Button(open ? "Fold" : "+\(length - 5) moves") { folded[id] = open }.font(.caption) }
        }.padding(.leading, 14).padding(.vertical, 3).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8)))
    }
}
private struct VariationSegment {
    var cells: [(Cell, String?)]
    var branches: [(Cell, String)]
}
func moveID(_ path: MovePath) -> String { "move-" + path.map(String.init).joined(separator: ".") }

/// Wrap variation moves to the available width rather than clipping a long line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        positions(proposal.width ?? 300, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = positions(bounds.width, subviews)
        for (index, view) in subviews.enumerated() { view.place(at: CGPoint(x: bounds.minX + result.points[index].x, y: bounds.minY + result.points[index].y), proposal: .unspecified) }
    }
    private func positions(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
