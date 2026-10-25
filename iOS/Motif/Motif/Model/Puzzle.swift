import Foundation

enum Side: String, Codable, CaseIterable, Sendable {
    case white = "w", black = "b"
    var opposite: Side { self == .white ? .black : .white }
}

enum PieceType: String, Codable, CaseIterable, Sendable {
    case pawn = "p", knight = "n", bishop = "b", rook = "r", queen = "q", king = "k"
}

/// A piece and its square, the answer to a missing-piece puzzle. It is not a
/// move: nothing travels from anywhere, so it must not be squeezed into UCI.
struct Placement: Hashable, Codable, Sendable {
    var color: Side
    var type: PieceType
    var square: String
}

/// Whether a puzzle has ever been completed, and how.
enum PuzzleStatus: String, Codable, Sendable {
    case unseen, solved, failed
}

/// FEN-style notation: case carries colour; an explicit w/b prefix overrides
/// it for authors accustomed to uppercase SAN letters for either side.
func parsePlacement(_ text: String) -> Placement? {
    let whitespace = CharacterSet(charactersIn: Uci.whitespace)
    let normalized = String(String.UnicodeScalarView(text.unicodeScalars.map {
        whitespace.contains($0) ? UnicodeScalar(32)! : $0
    })).trimmingCharacters(in: whitespace)
    let pattern = #"^(?:([wb])[ -]*)?([pnbrqkPNBRQK])[ -]*([a-h][1-8])$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
          match.range.length == normalized.utf16.count else { return nil }
    func capture(_ index: Int) -> String? {
        Range(match.range(at: index), in: normalized).map { String(normalized[$0]) }
    }
    guard let piece = capture(2), let square = capture(3),
          let type = PieceType(rawValue: piece.lowercased()) else { return nil }
    let color = capture(1).flatMap(Side.init(rawValue:))
        ?? (piece == piece.uppercased() ? .white : .black)
    return Placement(color: color, type: type, square: square)
}

/// The canonical written form, e.g. Ng6; round-trips through parsePlacement.
func placementText(_ placement: Placement) -> String {
    (placement.color == .white ? placement.type.rawValue.uppercased() : placement.type.rawValue)
        + placement.square
}

func samePlacement(_ a: Placement, _ b: Placement) -> Bool { a == b }

/// Shared position/answer fields for full puzzles and imported content.
protocol PuzzleIdentity {
    var fen: String { get }
    var solutions: [[Uci]] { get }
    var addPiece: Placement? { get }
}

struct Puzzle: Hashable, Codable, Sendable, PuzzleIdentity {
    var id: String
    /// Each puzzle belongs to exactly one collection.
    var collectionId: String
    /// Order within its collection.
    var position: Int
    var fen: String
    /// Alternating solver/reply lines; shared prefixes merge in the trie.
    /// Empty for a missing-piece puzzle.
    var solutions: [[Uci]]
    /// The kind is derived from this answer, so kind and data cannot disagree.
    var addPiece: Placement? = nil
    /// The idea and free-form note are spoilers; neither appears while solving.
    var tags: [String] = []
    var comment: String? = nil
    /// Set in-app, never by a file, so re-importing preserves it.
    var flagged: Bool? = nil
    /// The book's puzzle number, not a dedupe key.
    var sourceId: String? = nil
    var rating: Double? = nil
    var addedAt: Int64

    var content: PuzzleContent {
        PuzzleContent(fen: fen, solutions: solutions, addPiece: addPiece, tags: tags,
                      comment: comment, sourceId: sourceId, rating: rating)
    }

    init(id: String, collectionId: String, position: Int, fen: String, solutions: [[Uci]],
         addPiece: Placement? = nil, tags: [String] = [], comment: String? = nil,
         flagged: Bool? = nil, sourceId: String? = nil, rating: Double? = nil, addedAt: Int64) {
        self.id = id; self.collectionId = collectionId; self.position = position
        self.fen = fen; self.solutions = solutions; self.addPiece = addPiece
        self.tags = tags; self.comment = comment; self.flagged = flagged
        self.sourceId = sourceId; self.rating = rating; self.addedAt = addedAt
    }

    init(content: PuzzleContent, id: String, collectionId: String, position: Int, addedAt: Int64) {
        self.init(id: id, collectionId: collectionId, position: position, fen: content.fen,
                  solutions: content.solutions, addPiece: content.addPiece, tags: content.tags,
                  comment: content.comment, sourceId: content.sourceId, rating: content.rating,
                  addedAt: addedAt)
    }
}

/// What a puzzle is, apart from where it is kept: the part a file supplies.
struct PuzzleContent: Hashable, Codable, Sendable, PuzzleIdentity {
    var fen: String
    var solutions: [[Uci]]
    var addPiece: Placement? = nil
    var tags: [String] = []
    var comment: String? = nil
    var sourceId: String? = nil
    var rating: Double? = nil
}

struct Collection: Hashable, Codable, Sendable {
    var id: String
    var name: String
    var createdAt: Int64
}

func isMissingPiece(_ puzzle: some PuzzleIdentity) -> Bool { puzzle.addPiece != nil }

/// Keep the four fields defining a position. Move counters do not identify it.
func normalizeFen(_ fen: String) -> String {
    fen.trimmingCharacters(in: CharacterSet(charactersIn: Uci.whitespace))
        .components(separatedBy: CharacterSet(charactersIn: Uci.whitespace))
        .filter { !$0.isEmpty }.prefix(4).joined(separator: " ")
}

/// Identity for import dedupe, deliberately excluding metadata so re-imports
/// update rather than fork. Answer order does not affect identity.
func contentKey(_ puzzle: some PuzzleIdentity) -> String {
    let lines = puzzle.solutions.map { $0.map(\.text).joined(separator: " ") }
        .sorted().joined(separator: "|")
    let placement = puzzle.addPiece.map(placementText) ?? "-"
    return "\(normalizeFen(puzzle.fen))/\(lines)/\(placement)"
}

/// Missing-piece answers use the piece's colour, which may differ from turn.
func solverSide(_ puzzle: some PuzzleIdentity) -> Side {
    if let piece = puzzle.addPiece { return piece.color }
    return normalizeFen(puzzle.fen).split(separator: " ").dropFirst().first == "b" ? .black : .white
}
