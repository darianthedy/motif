import Foundation

func gameCollectionsOf(_ library: Library) -> [GameCollection] {
    library.gameCollections.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
}
func gamesIn(_ library: Library, _ collectionId: String) -> [Game] {
    library.games.filter { $0.collectionId == collectionId }.sorted {
        $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position
    }
}
private func nextPosition(_ library: Library, _ collectionId: String) -> Int {
    gamesIn(library, collectionId).reduce(0) { max($0, $1.position + 1) }
}

/// New games append in the given order with device-generated ids.
func appendGames(_ library: Library, _ collectionId: String, _ games: [GameContent]) -> [NewGame] {
    let start = nextPosition(library, collectionId)
    return games.enumerated().map { n, game in
        NewGame(id: UUID().uuidString.lowercased(), collectionId: collectionId,
                position: start + n, pgn: game.pgn, orientation: game.orientation)
    }
}
func copyGames(_ library: Library, _ games: [Game], _ collectionId: String) -> [NewGame] {
    appendGames(library, collectionId, games.map { GameContent(pgn: $0.pgn, orientation: $0.orientation) })
}
/// Moving within the destination is skipped; other games keep the given order.
func moveGames(_ library: Library, _ games: [Game], _ collectionId: String) -> [GamePlacement] {
    let start = nextPosition(library, collectionId)
    return games.filter { $0.collectionId != collectionId }.enumerated().map { n, game in
        GamePlacement(id: game.id, collectionId: collectionId, position: start + n)
    }
}
enum GameShift: Int, Sendable { case up = -1, down = 1 }

/// Swap with a neighbour, renumbering the pair even if their positions tie.
func shiftGame(_ library: Library, _ game: Game, _ by: GameShift) -> [GamePlacement] {
    let games = gamesIn(library, game.collectionId)
    guard let index = games.firstIndex(where: { $0.id == game.id }),
          games.indices.contains(index + by.rawValue) else { return [] }
    let other = games[index + by.rawValue]
    let low = min(game.position, other.position)
    let pair = by == .up ? [game, other] : [other, game]
    return pair.enumerated().map { n, game in
        GamePlacement(id: game.id, collectionId: game.collectionId, position: low + n)
    }
}
