/// A node awaits the solver's move. Each edge carries the scripted defence,
/// so continuations against different defences never silently merge.
struct TrieNode: Sendable {
    /// Moves and their defence variants in declaration order.
    var edges: [TrieMove] = []
    /// Earliest-declared move reaching this node: the author's hint mainline.
    var preferredMove: Uci? = nil
}

struct TrieMove: Sendable {
    var move: Uci
    var variants: [TrieEdge]
}

struct TrieEdge: Sendable {
    /// A reply and a terminal next node are independent: a line may end on
    /// the opponent's forced move, which still has to be played.
    var reply: Uci?
    var next: TrieNode
}

func isTerminal(_ node: TrieNode) -> Bool { node.edges.isEmpty }

func buildTrie(_ solutions: [[Uci]]) -> TrieNode {
    var root = TrieNode()
    for line in solutions { insert(line, at: 0, into: &root) }
    return root
}

private func insert(_ line: [Uci], at ply: Int, into node: inout TrieNode) {
    guard ply < line.count else { return }
    let move = line[ply]
    let reply = ply + 1 < line.count ? line[ply + 1] : nil
    if node.preferredMove == nil { node.preferredMove = move }
    let moveIndex: Int
    if let existing = node.edges.firstIndex(where: { $0.move == move }) {
        moveIndex = existing
    } else {
        moveIndex = node.edges.count
        node.edges.append(TrieMove(move: move, variants: []))
    }
    let variants = node.edges[moveIndex].variants
    // A shorter line joins the first variant, and a longer one fills the blank
    // it left. Only two explicitly different replies fork their continuations.
    let existing = reply == nil ? variants.indices.first
        : (variants.firstIndex { $0.reply == reply } ?? variants.firstIndex { $0.reply == nil })
    let variantIndex: Int
    if let existing {
        variantIndex = existing
        if node.edges[moveIndex].variants[existing].reply == nil {
            node.edges[moveIndex].variants[existing].reply = reply
        }
    } else {
        variantIndex = variants.count
        node.edges[moveIndex].variants.append(TrieEdge(reply: reply, next: TrieNode()))
    }
    insert(line, at: ply + 2, into: &node.edges[moveIndex].variants[variantIndex].next)
}

/// Exact match first, then only an explicit queen may match omitted promotion.
/// The first defence variant is the author's played answer.
func findEdge(_ node: TrieNode, _ move: Uci) -> TrieEdge? {
    if let exact = node.edges.first(where: { $0.move == move })?.variants.first { return exact }
    guard let stripped = stripQueenPromotion(move) else { return nil }
    return node.edges.first(where: { $0.move == stripped })?.variants.first
}
