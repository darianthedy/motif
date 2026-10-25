struct Cell: Equatable, Codable, Sendable {
    var node: MoveNode
    var path: MovePath
}
enum TableItem: Equatable, Sendable {
    case row(number: Double, white: Cell?, black: Cell?)
    case variations(fen: String, alternatives: [Cell])
}

/// Book-style rows pair White/Black. Alternatives follow and break their row,
/// so a White alternative makes Black's reply start a row on its own.
func moveTable(_ game: ParsedGame) -> [TableItem] {
    var items: [TableItem] = []
    var rowIndex: Int?
    var nodes = game.moves
    var fen = game.startFen
    var at: MovePath = []
    while let main = nodes.first {
        let cell = Cell(node: main, path: at + [0])
        let fields = fen.components(separatedBy: " ")
        let side = fields.count > 1 ? fields[1] : ""
        let number = fields.count > 5 ? Double(fields[5]) ?? .nan : .nan
        if side == "w" {
            rowIndex = items.count
            items.append(.row(number: number, white: cell, black: nil))
        } else if let index = rowIndex,
                  case .row(let rowNumber, let white, nil) = items[index], rowNumber == number {
            items[index] = .row(number: number, white: white, black: cell)
        } else {
            rowIndex = items.count
            items.append(.row(number: number, white: nil, black: cell))
        }
        if nodes.count > 1 {
            items.append(.variations(fen: fen, alternatives: nodes.dropFirst().enumerated().map {
                Cell(node: $0.element, path: at + [$0.offset + 1])
            }))
            rowIndex = nil
        }
        fen = main.fen; at = cell.path; nodes = main.children
    }
    return items
}
/// Follow only this line's main continuation.
func lineLength(_ node: MoveNode) -> Int {
    var length = 1
    var next = node.children.first
    while let held = next { length += 1; next = held.children.first }
    return length
}
/// Include every branch after a move.
func movesFrom(_ node: MoveNode) -> Int { 1 + node.children.reduce(0) { $0 + movesFrom($1) } }
func startsWith(_ path: MovePath, _ prefix: MovePath) -> Bool {
    prefix.count <= path.count && path.prefix(prefix.count).elementsEqual(prefix)
}
