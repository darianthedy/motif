import Foundation

/// Moves use validated UCI strings because lookups compare them by value.
/// SAN stays out of the model's hot path; the board converts it for display.
struct Uci: Hashable, Codable, Sendable {
    let text: String
    // ECMAScript trim/\s includes BOM and excludes the Unicode NEL character.
    static let whitespace = "\u{9}\u{A}\u{B}\u{C}\u{D} \u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}"

    private init(validated text: String) { self.text = text }

    /// Validates and normalizes a UCI string. Returns nil for anything else.
    static func parse(_ text: String) -> Uci? {
        let lower = text.trimmingCharacters(in: CharacterSet(charactersIn: whitespace)).lowercased()
        guard lower.range(of: "^[a-h][1-8][a-h][1-8][qrbn]?$",
                          options: .regularExpression) != nil,
              lower.utf8.count == 4 || lower.utf8.count == 5 else { return nil }
        return Uci(validated: lower)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let parsed = Self.parse(value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a UCI move: \(value)")
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

enum PromotionPiece: String, Codable, CaseIterable, Sendable {
    case queen = "q", rook = "r", bishop = "b", knight = "n"
}

enum MoveError: Error { case invalidUci(String) }

func parseUci(_ text: String) -> Uci? { Uci.parse(text) }

/// Throws on bad input. For literals in tests and seed data, not imports.
func uci(_ text: String) throws -> Uci {
    guard let parsed = parseUci(text) else { throw MoveError.invalidUci(text) }
    return parsed
}

func moveFrom(_ move: Uci) -> String { String(move.text.prefix(2)) }
func moveTo(_ move: Uci) -> String { String(move.text.dropFirst(2).prefix(2)) }
func movePromotion(_ move: Uci) -> PromotionPiece? {
    move.text.count == 5 ? PromotionPiece(rawValue: String(move.text.suffix(1))) : nil
}
func makeMove(_ from: String, _ to: String, _ promotion: PromotionPiece? = nil) throws -> Uci {
    try uci(from + to + (promotion?.rawValue ?? ""))
}

/// Only an explicit queen may retry a solution written without promotion.
/// Underpromotions keep their identity and never take this path.
func stripQueenPromotion(_ move: Uci) -> Uci? {
    movePromotion(move) == .queen ? parseUci(String(move.text.prefix(4))) : nil
}
