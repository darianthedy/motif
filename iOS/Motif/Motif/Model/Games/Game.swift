/// Games are read, not solved, so their collections have no runs or progress.
struct GameCollection: Hashable, Codable, Sendable {
    var id: String
    var name: String
    var createdAt: Int64
}

struct Game: Hashable, Codable, Sendable {
    /// Device-assigned so an added game can be opened immediately.
    var id: String
    var collectionId: String
    var position: Int
    /// The whole game: headers, moves, comments and variations.
    var pgn: String
    /// Kept so a flipped board stays flipped.
    var orientation: Side
    var addedAt: Int64
}

struct NewGame: Hashable, Codable, Sendable {
    var id: String
    var collectionId: String
    var position: Int
    var pgn: String
    var orientation: Side
}

/// Only the location/order changes when a game moves.
struct GamePlacement: Hashable, Codable, Sendable {
    var id: String
    var collectionId: String
    var position: Int
}

/// The two fields a file supplies before collection placement.
struct GameContent: Hashable, Codable, Sendable {
    var pgn: String
    var orientation: Side
}
