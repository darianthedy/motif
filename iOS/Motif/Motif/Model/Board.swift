import Foundation
import ChessKit

/// The only public boundary that knows chess rules. Runners and tries work on
/// UCI strings: an illegal drag is free, while a legal wrong move is a mistake.
///
/// ChessKit supplies ordinary legal moves. The adapter owns chess.js-compatible
/// FEN validation/output, special-move metadata, and canonical/loose SAN.
enum Board {
    struct Piece: Hashable, Codable, Sendable {
        var square: String
        var type: PieceType
        var color: Side
    }

    struct Target: Equatable, Codable, Sendable {
        var promotion: Bool
        var capture: Bool
    }

    struct FenValidation: Equatable, Codable, Sendable {
        let ok: Bool
        var error: String? = nil
    }

    struct IllegalMove: Equatable, Codable, Sendable {
        let move: Uci
        let ply: Int
    }

    struct ReplayStep: Equatable, Codable, Sendable {
        let san: String
        let move: Uci
        let fen: String
        let bySolver: Bool
    }

    struct PlayedSan: Equatable, Codable, Sendable {
        let san: String
        let uci: Uci
        let fenAfter: String
    }

    /// All 64 squares, a1 first, in rank-major order.
    static let squares = (1...8).flatMap { rank in "abcdefgh".map { "\($0)\(rank)" } }
    static let defaultPosition = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    /// Mirrors chess.js validateFen, including its parseInt counter semantics.
    /// Loading a FEN separately fills commonly omitted fields, just as Chess does.
    static func validateFen(_ fen: String) -> FenValidation {
        let fields = tokens(fen)
        func invalid(_ error: String) -> FenValidation { .init(ok: false, error: "Invalid FEN: " + error) }
        guard fields.count == 6 else { return invalid("must contain six space-delimited fields") }
        guard let full = integerPrefix(fields[5]), full > 0 else { return invalid("move number must be a positive integer") }
        guard let half = integerPrefix(fields[4]), half >= 0 else { return invalid("half move counter number must be a non-negative integer") }
        guard matches(fields[3], "^(-|[abcdefgh][36])$") else { return invalid("en-passant square is invalid") }
        guard !matches(fields[2], "[^kKqQ-]") else { return invalid("castling availability is invalid") }
        guard fields[1] == "w" || fields[1] == "b" else { return invalid("side-to-move is invalid") }
        let rows = fields[0].components(separatedBy: "/")
        guard rows.count == 8 else { return invalid("piece data does not contain 8 '/'-delimited rows") }
        for row in rows {
            var sum = 0
            var previousWasNumber = false
            for character in row {
                let text = String(character)
                if "0123456789".contains(character) {
                    if previousWasNumber { return invalid("piece data is invalid (consecutive number)") }
                    sum += Int(text)!
                    previousWasNumber = true
                } else {
                    guard "prnbqkPRNBQK".contains(character) else { return invalid("piece data is invalid (invalid piece)") }
                    sum += 1
                    previousWasNumber = false
                }
            }
            guard sum == 8 else { return invalid("piece data is invalid (too many squares in rank)") }
        }
        if (fields[3].last == "3" && fields[1] == "w") || (fields[3].last == "6" && fields[1] == "b") {
            return invalid("illegal en-passant square")
        }
        for (side, king) in [("white", Character("K")), ("black", Character("k"))] {
            let count = fields[0].filter { $0 == king }.count
            guard count > 0 else { return invalid("missing \(side) king") }
            guard count == 1 else { return invalid("too many \(side) kings") }
        }
        guard !(rows[0] + rows[7]).contains(where: { $0 == "p" || $0 == "P" }) else {
            return invalid("some pawns are on the edge rows")
        }
        // The actual web validator accepts check on the non-moving side and
        // stale castling rights. Adding stricter checks would change the spec.
        return .init(ok: true)
    }

    static func isValidFen(_ fen: String) -> Bool { load(fen) != nil }

    /// Whether the side to move is mated. False for a position that cannot load.
    static func isCheckmate(_ fen: String) -> Bool {
        guard let position = load(fen) else { return false }
        return inCheck(position, position.side) && legalMoves(position).isEmpty
    }

    static func turnOf(_ fen: String) -> Side? { load(fen)?.side }

    /// Promotion variants collapse into one destination so the board can ask
    /// for a piece after the user chooses where to land. Captures ring the square.
    static func targetsFrom(_ fen: String, _ from: String) -> [String: Target] {
        guard let position = load(fen) else { return [:] }
        // chess.js lowercases this query; an empty query requests all pieces.
        let start = from.isEmpty ? nil : index(from.lowercased())
        guard from.isEmpty || start != nil else { return [:] }
        var targets: [String: Target] = [:]
        for move in legalMoves(position, from: start) {
            let destination = squares[move.to]
            let existing = targets[destination]
            targets[destination] = .init(
                promotion: existing?.promotion == true || move.promotion != nil,
                capture: existing?.capture == true || move.capture
            )
        }
        return targets
    }

    static func isLegal(_ fen: String, _ move: Uci) -> Bool { applyUci(fen, move) != nil }

    /// Illegal moves are ordinary mis-drags; return nil, never throw.
    static func applyUci(_ fen: String, _ move: Uci) -> String? {
        guard let position = movePosition(fen), let legal = find(move, in: position) else { return nil }
        return output(applying(legal, to: position))
    }

    /// SAN for display. Nil when the move is illegal in this position.
    static func sanFor(_ fen: String, _ move: Uci) -> String? {
        guard let position = movePosition(fen) else { return nil }
        let moves = legalMoves(position)
        guard let legal = moves.first(where: { agrees($0, with: move) }) else { return nil }
        return san(legal, in: position, legal: moves)
    }

    /// Decide whether to open the promotion picker before committing a move.
    static func needsPromotion(_ fen: String, _ from: String, _ to: String) -> Bool {
        targetsFrom(fen, from)[to]?.promotion ?? false
    }

    /// Reject an unsolvable imported line rather than stranding the session on
    /// a hint the board cannot accept. Each solution starts at the original FEN.
    static func firstIllegalMove(_ fen: String, _ solutions: [[Uci]]) -> IllegalMove? {
        for line in solutions {
            var position = fen
            for (ply, move) in line.enumerated() {
                guard let next = applyUci(position, move) else { return .init(move: move, ply: ply) }
                position = next
            }
        }
        return nil
    }

    static func pieceAt(_ fen: String, _ square: String) -> Piece? {
        guard let position = load(fen), let square = index(square) else { return nil }
        return position.cells[square]
    }

    /// The missing-piece counterpart of applyUci: occupied squares and pawn
    /// edge ranks are ordinary mis-hits. Never silently replace an authored piece.
    static func withPiece(_ fen: String, _ placement: Placement) -> String? {
        guard var position = load(fen), let square = index(placement.square),
              position.cells[square] == nil else { return nil }
        if placement.type == .pawn && (square / 8 == 0 || square / 8 == 7) { return nil }
        if placement.type == .king && position.cells.contains(where: {
            $0?.type == .king && $0?.color == placement.color
        }) { return nil }
        position.cells[square] = .init(square: placement.square, type: placement.type, color: placement.color)
        updatePutMetadata(&position)
        let next = output(position)
        return isValidFen(next) ? next : nil
    }

    /// Only empty squares can receive a missing piece; order remains a1 first.
    static func emptySquares(_ fen: String) -> [String] {
        guard let position = load(fen) else { return [] }
        return squares.indices.filter { position.cells[$0] == nil }.map { squares[$0] }
    }

    /// Audit missing-piece puzzles for more than one correct mating placement.
    /// Kings are not candidates; preserve the web's square/type iteration order.
    static func matingPlacements(_ fen: String, _ color: Side) -> [Placement] {
        var found: [Placement] = []
        for square in emptySquares(fen) {
            for type: PieceType in [.queen, .rook, .bishop, .knight, .pawn] {
                let placement = Placement(color: color, type: type, square: square)
                if let next = withPiece(fen, placement), isCheckmate(next) { found.append(placement) }
            }
        }
        return found
    }

    /// Browsing an old puzzle stops at the first illegal ply, while still
    /// rendering the valid prefix of a line predating import-time validation.
    static func replayLine(_ fen: String, _ line: [Uci]) -> [ReplayStep] {
        var steps: [ReplayStep] = []
        var position = fen
        for (ply, move) in line.enumerated() {
            guard let san = sanFor(position, move), let next = applyUci(position, move) else { break }
            steps.append(.init(san: san, move: move, fen: next, bySolver: ply % 2 == 0))
            position = next
        }
        return steps
    }

    /// Loose SAN follows chess.js strict:false, including LAN, unnecessary
    /// disambiguation, missing check decorations, and zero-spelled castling.
    static func playSan(_ fen: String, _ text: String) -> PlayedSan? {
        guard var position = movePosition(fen) else { return nil }
        var clean = strippedSan(text)
        if clean == "0-0" { clean = "O-O" }
        if clean == "0-0-0" { clean = "O-O-O" }
        if clean == "--" {
            guard !inCheck(position, position.side) else { return nil }
            position.half += 1
            if position.side == .black { position.full += 1 }
            position.side = position.side.opposite
            position.ep = "-"
            return .init(san: "--", uci: Uci.parse("a8a8")!, fenAfter: output(position))
        }
        let all = legalMoves(position)
        let inferred = inferPieceType(clean)
        let strict = all.filter { inferred == nil || position.cells[$0.from]?.type.rawValue == inferred }
        if let move = strict.first(where: { strippedSan(san($0, in: position, legal: all)) == clean }) {
            return played(move, in: position, legal: all)
        }
        let full = captures(clean, "([pnbrqkPNBRQK])?([a-h][1-8])x?-?([a-h][1-8])([qrbnQRBN])?")
        let groups = full ?? captures(clean, "([pnbrqkPNBRQK])?([a-h]?[1-8]?)x?-?([a-h][1-8])([qrbnQRBN])?")
        guard let groups else { return nil }
        let piece = groups[1]
        let from = groups[2]
        let to = groups[3]
        let promotion = groups[4].lowercased()
        let candidates = all.filter {
            position.cells[$0.from]?.type.rawValue == (piece.isEmpty ? inferred : piece.lowercased()) ||
                (piece.isEmpty && inferred == nil)
        }
        for move in candidates {
            if from.isEmpty {
                if clean == strippedSan(san(move, in: position, legal: all)).replacingOccurrences(of: "x", with: "") {
                    return played(move, in: position, legal: all)
                }
            } else if squares[move.to] == to &&
                        (promotion.isEmpty || promotion == move.promotion?.rawValue) &&
                        (squares[move.from] == from || (from.count == 1 && squares[move.from].contains(from))) {
                return played(move, in: position, legal: all)
            }
        }
        return nil
    }

    // MARK: ChessKit adapter

    private struct Position {
        var cells: [Piece?]
        var side: Side
        var rights: String
        var ep: String
        var half: Double
        var full: Double
    }

    private struct LegalMove {
        let from: Int
        let to: Int
        var promotion: PromotionPiece? = nil
        var capture = false
        var ep = false
        var castle = false
    }

    private static func legalMoves(_ position: Position, from requested: Int? = nil) -> [LegalMove] {
        // Use a normalized board and no special rights here. The adapter handles
        // EP and castling because ChessKit has different metadata/validation.
        let fen = placement(position) + " \(position.side.rawValue) - - 0 1"
        guard let parsed = ChessKit.Position(fen: fen) else { return [] }
        let engine = ChessKit.Board(position: parsed)
        var result: [LegalMove] = []
        // chess.js visits ranks from 8 to 1. This also fixes permissive SAN's
        // first-candidate choice and promotion order (n, b, r, q).
        let starts = requested.map { [$0] } ?? (0..<64).sorted { mailbox($0) < mailbox($1) }
        for from in starts {
            guard let piece = position.cells[from], piece.color == position.side else { continue }
            for destination in engine.legalMoves(forPieceAt: ChessKit.Square(squares[from])) {
                let to = destination.rawValue
                let promotions: [PromotionPiece?] = piece.type == .pawn && (to / 8 == 0 || to / 8 == 7)
                    ? [.knight, .bishop, .rook, .queen] : [nil]
                for promotion in promotions {
                    result.append(.init(from: from, to: to, promotion: promotion,
                                        capture: position.cells[to] != nil))
                }
            }
            if piece.type == .pawn, let to = index(position.ep),
               abs(from % 8 - to % 8) == 1,
               to / 8 - from / 8 == (piece.color == .white ? 1 : -1),
               position.cells[to]?.color != piece.color.opposite {
                let move = LegalMove(from: from, to: to, capture: true, ep: true)
                if !inCheck(applying(move, to: position), piece.color) { result.append(move) }
            }
            if piece.type == .king {
                let rights: [(Character, Int)] = piece.color == .white ? [("K", 1), ("Q", -1)] : [("k", 1), ("q", -1)]
                for (right, direction) in rights where position.rights.contains(right) {
                    let to = from + 2 * direction
                    let path = direction == 1 ? [from + 1, to] : [from - 1, to, from - 3]
                    guard path.allSatisfy({ (0..<64).contains($0) && $0 / 8 == from / 8 && position.cells[$0] == nil }),
                          !attacked(from, by: piece.color.opposite, in: position),
                          !attacked(from + direction, by: piece.color.opposite, in: position),
                          !attacked(to, by: piece.color.opposite, in: position) else { continue }
                    result.append(.init(from: from, to: to, castle: true))
                }
            }
        }
        return result
    }

    private static func applying(_ move: LegalMove, to original: Position) -> Position {
        var next = original
        guard var piece = next.cells[move.from] else { return next }
        next.cells[move.from] = nil
        piece.square = squares[move.to]
        if let promotion = move.promotion { piece.type = PieceType(rawValue: promotion.rawValue)! }
        next.cells[move.to] = piece
        if move.ep { next.cells[move.to + (original.side == .white ? -8 : 8)] = nil }
        if move.castle {
            let direction = move.to > move.from ? 1 : -1
            let rookFrom = move.from + (direction == 1 ? 3 : -4)
            let rookTo = move.to - direction
            if (0..<64).contains(rookFrom) {
                next.cells[rookTo] = next.cells[rookFrom]
                next.cells[rookTo]?.square = squares[rookTo]
                next.cells[rookFrom] = nil
            }
        }
        let originalPiece = original.cells[move.from]!
        if originalPiece.type == .king {
            let rights = original.side == .white ? "KQ" : "kq"
            next.rights.removeAll { rights.contains($0) }
        }
        // chess.js revokes corner rights on movement/capture even when a loaded
        // position has stale rights and the corner contains a different piece.
        for (square, right) in [(0, Character("Q")), (7, "K"), (56, "q"), (63, "k")] {
            if (move.from == square && originalPiece.color == (square < 8 ? .white : .black)) ||
                (move.to == square && originalPiece.color != (square < 8 ? .white : .black)) {
                next.rights.removeAll { $0 == right }
            }
        }
        next.ep = originalPiece.type == .pawn && abs(move.to - move.from) == 16
            ? squares[(move.to + move.from) / 2] : "-"
        next.half = originalPiece.type == .pawn || move.capture ? 0 : original.half + 1
        next.full = original.full + (original.side == .black ? 1 : 0)
        next.side = original.side.opposite
        return next
    }

    private static func attacked(_ target: Int, by color: Side, in position: Position) -> Bool {
        for (from, optional) in position.cells.enumerated() {
            guard let piece = optional, piece.color == color else { continue }
            let dx = target % 8 - from % 8
            let dy = target / 8 - from / 8
            switch piece.type {
            case .pawn:
                if abs(dx) == 1 && dy == (color == .white ? 1 : -1) { return true }
            case .knight:
                if (abs(dx) == 1 && abs(dy) == 2) || (abs(dx) == 2 && abs(dy) == 1) { return true }
            case .king:
                if max(abs(dx), abs(dy)) == 1 { return true }
            case .bishop, .rook, .queen:
                let diagonal = abs(dx) == abs(dy) && dx != 0
                let straight = (dx == 0) != (dy == 0)
                guard (piece.type != .rook && diagonal) || (piece.type != .bishop && straight) else { continue }
                let step = (dx == 0 ? 0 : dx > 0 ? 1 : -1) + 8 * (dy == 0 ? 0 : dy > 0 ? 1 : -1)
                var square = from + step
                while square != target && position.cells[square] == nil { square += step }
                if square == target { return true }
            }
        }
        return false
    }

    private static func inCheck(_ position: Position, _ color: Side) -> Bool {
        guard let king = position.cells.firstIndex(where: { $0?.type == .king && $0?.color == color }) else { return false }
        return attacked(king, by: color.opposite, in: position)
    }

    private static func san(_ move: LegalMove, in position: Position, legal: [LegalMove]) -> String {
        let piece = position.cells[move.from]!
        var text = ""
        if move.castle {
            text = move.to > move.from ? "O-O" : "O-O-O"
        } else {
            if piece.type != .pawn {
                text = piece.type.rawValue.uppercased()
                if piece.type != .king {
                    let others = legal.filter { $0.from != move.from && $0.to == move.to &&
                        position.cells[$0.from]?.type == piece.type }
                    if !others.isEmpty {
                        let fileConflict = others.contains { $0.from % 8 == move.from % 8 }
                        let rankConflict = others.contains { $0.from / 8 == move.from / 8 }
                        text += fileConflict ? (rankConflict ? squares[move.from] : String(squares[move.from].suffix(1)))
                            : String(squares[move.from].prefix(1))
                    }
                }
            } else if move.capture { text = String(squares[move.from].prefix(1)) }
            if move.capture { text += "x" }
            text += squares[move.to]
            if let promotion = move.promotion { text += "=" + promotion.rawValue.uppercased() }
        }
        let after = applying(move, to: position)
        if inCheck(after, after.side) { text += legalMoves(after).isEmpty ? "#" : "+" }
        return text
    }

    private static func played(_ move: LegalMove, in position: Position, legal: [LegalMove]) -> PlayedSan {
        .init(san: san(move, in: position, legal: legal),
              uci: Uci.parse(squares[move.from] + squares[move.to] + (move.promotion?.rawValue ?? ""))!,
              fenAfter: output(applying(move, to: position)))
    }

    private static func agrees(_ legal: LegalMove, with move: Uci) -> Bool {
        squares[legal.from] == moveFrom(move) && squares[legal.to] == moveTo(move) &&
            (legal.promotion == nil || legal.promotion == movePromotion(move))
    }

    private static func find(_ move: Uci, in position: Position) -> LegalMove? {
        legalMoves(position, from: index(moveFrom(move))).first { agrees($0, with: move) }
    }

    // MARK: FEN parity

    private static func load(_ fen: String) -> Position? {
        var fields = tokens(fen)
        if (2..<6).contains(fields.count) {
            fields += Array(["-", "-", "0", "1"].suffix(6 - fields.count))
        }
        guard validateFen(fields.joined(separator: " ")).ok else { return nil }
        var cells = [Piece?](repeating: nil, count: 64)
        for (row, rank) in fields[0].components(separatedBy: "/").enumerated() {
            var file = 0
            for character in rank {
                if let empty = Int(String(character)) { file += empty } else {
                    let square = (7 - row) * 8 + file
                    cells[square] = .init(square: squares[square],
                                         type: PieceType(rawValue: String(character).lowercased())!,
                                         color: character.isUppercase ? .white : .black)
                    file += 1
                }
            }
        }
        return .init(cells: cells, side: Side(rawValue: fields[1])!,
                     rights: String("KQkq".filter { fields[2].contains($0) }),
                     ep: fields[3], half: integerPrefix(fields[4])!, full: integerPrefix(fields[5])!)
    }

    private static func movePosition(_ fen: String) -> Position? {
        guard var position = load(fen) else { return nil }
        // chess.js accepts an EP field with a missing captured pawn. Generating
        // and undoing the EP candidate restores that pawn before a move/SAN is
        // played. Preserve this observable behavior for legacy authored FENs.
        if let ep = index(position.ep) {
            let pawn = ep + (position.side == .white ? -8 : 8)
            if position.cells[pawn] == nil &&
                position.cells.enumerated().contains(where: { from, piece in
                    piece?.type == .pawn && piece?.color == position.side &&
                    abs(from % 8 - ep % 8) == 1 &&
                    ep / 8 - from / 8 == (position.side == .white ? 1 : -1)
                }) {
                position.cells[pawn] = .init(square: squares[pawn], type: .pawn, color: position.side.opposite)
            }
        }
        return position
    }

    private static func placement(_ position: Position) -> String {
        (0..<8).reversed().map { rank in
            var text = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = position.cells[rank * 8 + file] {
                    if empty > 0 { text += String(empty); empty = 0 }
                    text += piece.color == .white ? piece.type.rawValue.uppercased() : piece.type.rawValue
                } else { empty += 1 }
            }
            if empty > 0 { text += String(empty) }
            return text
        }.joined(separator: "/")
    }

    private static func output(_ position: Position) -> String {
        // Emit EP only if a legal capture exists, including the pinned-pawn case.
        var ep = "-"
        if let square = index(position.ep) {
            for from in 0..<64 where position.cells[from]?.type == .pawn && position.cells[from]?.color == position.side {
                if abs(from % 8 - square % 8) == 1 &&
                    square / 8 - from / 8 == (position.side == .white ? 1 : -1) {
                    let move = LegalMove(from: from, to: square, capture: true, ep: true)
                    if !inCheck(applying(move, to: position), position.side) { ep = position.ep; break }
                }
            }
        }
        return placement(position) + " \(position.side.rawValue) \(position.rights.isEmpty ? "-" : position.rights) \(ep) \(number(position.half)) \(number(position.full))"
    }

    private static func updatePutMetadata(_ position: inout Position) {
        for (right, king, rook, color) in [
            (Character("K"), 4, 7, Side.white), ("Q", 4, 0, .white),
            ("k", 60, 63, .black), ("q", 60, 56, .black)
        ] {
            if position.cells[king]?.type != .king || position.cells[king]?.color != color ||
                position.cells[rook]?.type != .rook || position.cells[rook]?.color != color {
                position.rights.removeAll { $0 == right }
            }
        }
        // On a freshly loaded chess.js board, put's empty-origin check clears
        // EP (its sparse board stores undefined rather than null). The web's
        // withPiece always loads a fresh board before calling put.
        position.ep = "-"
    }

    private static func number(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value.isInfinite { return value > 0 ? "Infinity" : "-Infinity" }
        let text = String(value).lowercased()
        let parts = text.components(separatedBy: "e")
        guard parts.count == 2, let exponent = Int(parts[1]) else {
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        }
        if exponent >= 21 { return parts[0].replacingOccurrences(of: ".0", with: "") + "e+\(exponent)" }
        let digits = parts[0].replacingOccurrences(of: ".", with: "")
        return digits + String(repeating: "0", count: max(0, exponent + 1 - digits.count))
    }

    private static func index(_ square: String) -> Int? { squares.firstIndex(of: square) }
    private static func mailbox(_ square: Int) -> Int { (7 - square / 8) * 16 + square % 8 }
    private static func tokens(_ text: String) -> [String] {
        text.replacingOccurrences(of: "[\(Uci.whitespace)]+", with: " ", options: .regularExpression).components(separatedBy: " ")
    }
    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
    private static func captures(_ text: String, _ pattern: String) -> [String]? {
        let regex = try! NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
    private static func integerPrefix(_ text: String) -> Double? {
        captures(text, "^[+-]?[0-9]+").flatMap { Double($0[0]) }
    }
    private static func strippedSan(_ text: String) -> String {
        var result = text
        if let equals = result.firstIndex(of: "=") { result.remove(at: equals) }
        return result.replacingOccurrences(of: "[+#]?[?!]*$", with: "", options: .regularExpression)
    }
    private static func inferPieceType(_ text: String) -> String? {
        guard let first = text.first else { return "" }
        if ("a"..."h").contains(String(first)) {
            return matches(text, "[a-h]\\d.*[a-h]\\d") ? nil : "p"
        }
        return first.lowercased() == "o" ? "k" : first.lowercased()
    }
}
