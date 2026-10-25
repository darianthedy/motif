import Foundation

enum BoardOutput: Equatable { case move(Uci), placement(Placement) }
enum BoardPending: Equatable { case promotion(String, String), placement(String) }

/// A gesture has one output or none. The board knows legality; its caller
/// decides whether a legal move answers the puzzle. Cancelling costs nothing.
struct BoardInteraction {
    var fen: String
    var interactive = true
    var placing: Side?
    private(set) var selected: String?
    private(set) var pending: BoardPending?
    var targets: [String: Board.Target] { selected.map { Board.targetsFrom(fen, $0) } ?? [:] }
    var choices: [PieceType] { if case .placement = pending { return [.queen, .rook, .bishop, .knight, .pawn] }; return [.queen, .rook, .bishop, .knight] }
    mutating func reset(_ fen: String) { self.fen = fen; selected = nil; pending = nil }
    mutating func cancel() { selected = nil; pending = nil }
    mutating func tap(_ square: String) -> BoardOutput? {
        guard interactive, pending == nil, Board.squares.contains(square) else { return nil }
        if placing != nil {
            if Board.pieceAt(fen, square) == nil { pending = .placement(square) }
            return nil
        }
        let own = Board.pieceAt(fen, square)?.color == Board.turnOf(fen) && Board.pieceAt(fen, square) != nil
        guard let from = selected else { selected = own ? square : nil; return nil }
        if from == square { selected = nil; return nil }
        if targets[square] != nil { return play(from, square) }
        selected = own ? square : nil
        return nil
    }
    mutating func drop(_ from: String, _ to: String?) -> BoardOutput? {
        selected = nil
        guard interactive, pending == nil, placing == nil, let to else { return nil }
        return play(from, to)
    }
    private mutating func play(_ from: String, _ to: String) -> BoardOutput? {
        guard Board.targetsFrom(fen, from)[to] != nil else { return nil }
        selected = nil
        if Board.needsPromotion(fen, from, to) { pending = .promotion(from, to); return nil }
        guard let move = try? makeMove(from, to), Board.isLegal(fen, move) else { return nil }
        return .move(move)
    }
    mutating func choose(_ piece: PieceType) -> BoardOutput? {
        guard interactive, let held = pending, choices.contains(piece) else { return nil }
        pending = nil
        switch held {
        case .promotion(let from, let to):
            guard let promotion = PromotionPiece(rawValue: piece.rawValue), let move = try? makeMove(from, to, promotion), Board.isLegal(fen, move) else { return nil }
            return .move(move)
        case .placement(let square):
            guard let color = placing, Board.pieceAt(fen, square) == nil else { return nil }
            return .placement(Placement(color: color, type: piece, square: square))
        }
    }
}
