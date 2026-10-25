import XCTest
@testable import Motif

let annotatedPGN = """
[Event "Club night"]
[Site "?"]
[Date "2024.03.??"]
[Round "?"]
[White "Me"]
[Black "Them"]
[Result "1-0"]

{An old favourite.} 1. e4 e5 (1... c5 {Sicilian} 2. Nf3 (2. c3) d6) 2. Nf3! Nc6
3. Bb5 $1 a6 (3... Nf6 4. O-O) 4. Ba4 ; to the end of the line
Nf6 1-0

"""
func testMainNodes(_ initial: [MoveNode]) -> [MoveNode] {
    var list = initial
    var nodes: [MoveNode] = []
    while let main = list.first { nodes.append(main); list = main.children }
    return nodes
}
func testMainLine(_ nodes: [MoveNode]) -> [String] { testMainNodes(nodes).map(\.san) }
func testStoredGame(_ id: String, _ collectionId: String, _ position: Int) -> Game {
    Game(id: id, collectionId: collectionId, position: position, pgn: "*", orientation: .white, addedAt: 0)
}
func testGameLibrary(_ games: [Game]) -> Library {
    Library(gameCollections: [
        GameCollection(id: "a", name: "A", createdAt: 0),
        GameCollection(id: "b", name: "B", createdAt: 1),
    ], games: games)
}
func testShowTable(_ items: [TableItem]) -> [String] {
    items.map {
        switch $0 {
        case .row(let number, let white, let black):
            return "\(Int(number)). \(white?.node.san ?? "…") \(black?.node.san ?? "…")"
        case .variations(_, let alternatives):
            return "( \(alternatives.map(\.node.san).joined(separator: " | ")) )"
        }
    }
}
