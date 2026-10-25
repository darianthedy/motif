import SwiftUI
struct MoveListView<MoveMenu: View>: View {
    let game: ParsedGame
    let path: MovePath
    let go: (MovePath) -> Void
    /// Called when the reader drags the list, not when it follows the moves.
    let scrolled: () -> Void
    @ViewBuilder let menu: (Cell) -> MoveMenu
    @State private var folded: [String: Bool] = [:]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(moveTable(game).enumerated()), id: \.offset) { _, item in
                        switch item {
                        case .row(let number, let white, let black):
                            HStack(spacing: 8) {
                                Text(number.formatted(.number.precision(.fractionLength(0))) + ".").font(.footnote).monospacedDigit().foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                                if let white { moveButton(white, number: nil).frame(maxWidth: .infinity, alignment: .leading) } else { Text("…").frame(maxWidth: .infinity, alignment: .leading) }
                                if let black { moveButton(black, number: nil).frame(maxWidth: .infinity, alignment: .leading) } else { Color.clear.frame(maxWidth: .infinity).frame(height: 1) }
                            }.frame(minHeight: 34)
                        case .variations(let fen, let alternatives):
                            ForEach(alternatives, id: \.path) { cell in variation(cell, fen: fen, depth: 0) }
                        }
                    }
                    if game.moves.isEmpty { Text("No moves yet. Play one on the board.").font(.footnote).foregroundStyle(.secondary).padding() }
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }.accessibilityIdentifier("game-move-list")
                .onScrollPhaseChange { _, phase in if phase == .interacting { scrolled() } }
                .onChange(of: path) { _, next in withAnimation { proxy.scrollTo(moveID(next), anchor: .center) } }
        }
    }
    private func moveButton(_ cell: Cell, number: String?, muted: Bool = false) -> some View {
        let text = (number.map { $0 + " " } ?? "") + cell.node.san + cell.node.nags.compactMap { NAG_SYMBOLS[$0] }.joined()
        let selected = cell.path == path
        return Button { go(cell.path) } label: {
            HStack(spacing: 4) {
                Text(text).font(.subheadline.weight(selected ? .semibold : .regular)).monospacedDigit()
                if !displayComment(cell.node.comment).isEmpty || !displayComment(cell.node.before).isEmpty {
                    Image(systemName: "text.bubble.fill").font(.caption2).foregroundStyle(selected ? Color.white : Color.secondary).accessibilityLabel("Has a comment")
                }
            }.foregroundStyle(selected ? Color.white : muted ? Color.primary.opacity(0.78) : Color.primary).padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Color.motifAccentStrong : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).id(moveID(cell.path)).accessibilityIdentifier(moveID(cell.path))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .contextMenu { menu(cell) }
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
        return AnyView(HStack(alignment: .firstTextBaseline, spacing: 0) {
            if length > 6 {
                Button { withAnimation(.snappy) { folded[id] = open } } label: {
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).rotationEffect(.degrees(open ? 0 : -90)).foregroundStyle(.secondary).frame(width: 22, height: 28)
                }.buttonStyle(.plain).accessibilityLabel(open ? "Fold variation" : "Unfold variation")
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    FlowLayout(spacing: 0) { ForEach(segment.cells, id: \.0.path) { cell, number in moveButton(cell, number: number, muted: true) } }
                    ForEach(segment.branches, id: \.0.path) { cell, position in variation(cell, fen: position, depth: depth + 1) }
                }
                if !open { Button("+\(length - 5) moves") { withAnimation(.snappy) { folded[id] = false } }.font(.caption).padding(.leading, 10) }
            }
        }.padding(.leading, 8).overlay(alignment: .leading) { Capsule().fill(Color(.systemGray4)).frame(width: 2) }
            .padding(.leading, depth == 0 ? 38 : 2).padding(.vertical, 3))
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
