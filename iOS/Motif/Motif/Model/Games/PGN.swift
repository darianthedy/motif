import Foundation

// PGN text is the stored game; the tree is always derived. This movetext
// reader retains variations that a main-line-only chess reader would discard.
// Move legality and resulting positions stay behind Board.playSan.

/// Headers preserve declaration order, including updates in place. JavaScript
/// object keys enumerate integer names first; PGN permits those names too.
/// Equality compares values like the web's object equality. A parsed tree is
/// derived from PGN, never the stored representation.
struct PgnHeaders: Equatable, Codable, Sendable {
    private var order: [String] = []
    private var values: [String: String] = [:]

    init(_ entries: [(String, String)] = []) {
        for (name, value) in entries { self[name] = value }
    }

    subscript(_ name: String) -> String? {
        get { values[name] }
        set {
            if let newValue {
                if values[name] == nil { order.append(name) }
                values[name] = newValue
            } else {
                values.removeValue(forKey: name)
                order.removeAll { $0 == name }
            }
        }
    }

    var names: [String] {
        func integer(_ name: String) -> UInt32? {
            guard let number = UInt32(name), number < UInt32.max, String(number) == name else { return nil }
            return number
        }
        return order.filter { integer($0) != nil }.sorted { integer($0)! < integer($1)! }
            + order.filter { integer($0) == nil }
    }
    var dictionary: [String: String] { values }
    static func == (a: Self, b: Self) -> Bool { a.values == b.values }

    init(from decoder: any Decoder) throws {
        let values = try [String: String](from: decoder)
        self.init(values.map { ($0.key, $0.value) })
    }
    func encode(to encoder: any Encoder) throws { try values.encode(to: encoder) }
}

struct MoveNode: Equatable, Codable, Sendable {
    var san: String
    var uci: Uci
    /// Position after the move.
    var fen: String
    /// Written before the move, introducing a variation.
    var before: String? = nil
    var comment: String? = nil
    var nags: [Int] = []
    /// Main line first, then alternatives.
    var children: [MoveNode] = []
}

struct ParsedGame: Equatable, Codable, Sendable {
    var headers: PgnHeaders
    var startFen: String
    /// Note before the first move.
    var comment: String? = nil
    var moves: [MoveNode] = []
}

struct PgnError: Equatable, Codable, Sendable {
    /// One-based game number in the file.
    var game: Int
    var message: String
}
struct PgnFile: Equatable, Codable, Sendable {
    var games: [ParsedGame] = []
    var errors: [PgnError] = []
}
struct PgnFailure: Error, Equatable, CustomStringConvertible {
    var message: String
    var description: String { message }
}

let RESULTS = ["1-0", "0-1", "1/2-1/2", "*"]
private let sevenTagRoster = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]
private let suffixNags = ["!": 1, "?": 2, "!!": 3, "??": 4, "!?": 5, "?!": 6]
/// Standard annotation symbols. Exports may write symbols as separate words.
let NAG_SYMBOLS: [Int: String] = [
    1: "!", 2: "?", 3: "!!", 4: "??", 5: "!?", 6: "?!", 7: "□", 10: "=",
    13: "∞", 14: "⩲", 15: "⩱", 16: "±", 17: "∓", 18: "+−", 19: "−+",
    22: "⨀", 32: "⟳", 36: "↑", 40: "→", 132: "⇆", 138: "⊕", 140: "∆", 146: "N",
]
private let wordNags: [String: Int] = {
    var map = Dictionary(uniqueKeysWithValues: NAG_SYMBOLS.map { ($0.value, $0.key) })
    for (word, nag) in ["+/=": 14, "=/+": 15, "+/-": 16, "-/+": 17, "+-": 18,
                        "-+": 19, "=+": 15, "+=": 14, "⊙": 22, "△": 140] { map[word] = nag }
    return map
}()

private enum PgnToken {
    case header(String, String), comment(String), open, close, nag(Int), result(String), move(String)
}
private let pgnWhitespace = CharacterSet(charactersIn: Uci.whitespace)
private let headerPattern = "\\[[" + Uci.whitespace + "]*([A-Za-z0-9_]+)[" + Uci.whitespace
    + "]*\"((?:[^\"\\\\]|\\\\[^\\n\\r\\u2028\\u2029])*)\"[" + Uci.whitespace + "]*\\]"

private func headerAtStart(_ text: String) -> (name: String, value: String, length: Int)? {
    let regex = try! NSRegularExpression(pattern: headerPattern)
    guard let match = regex.firstMatch(in: text, options: .anchored,
                                       range: NSRange(location: 0, length: text.utf16.count)),
          let name = Range(match.range(at: 1), in: text),
          let value = Range(match.range(at: 2), in: text) else { return nil }
    return (String(text[name]), unescapeHeader(String(text[value])), match.range.length)
}
private func unescapeHeader(_ value: String) -> String {
    let units = Array(value.utf16)
    var out: [UInt16] = []
    var i = 0
    while i < units.count {
        if units[i] == 92, i + 1 < units.count, ![10, 13, 0x2028, 0x2029].contains(units[i + 1]) { i += 1 }
        out.append(units[i])
        i += 1
    }
    return String(decoding: out, as: UTF16.self)
}

private func tokenizePgn(_ text: String) throws -> [PgnToken] {
    let units = Array(text.utf16)
    let spaces = Set(Uci.whitespace.utf16)
    let punctuation = Set("{}();[]$".utf16)
    var tokens: [PgnToken] = []
    var i = 0
    func slice(_ start: Int, _ end: Int) -> String { String(decoding: units[start..<end], as: UTF16.self) }
    func restOfLine() -> String {
        let start = i
        while i < units.count && units[i] != 10 { i += 1 }
        let line = slice(start, i)
        if i < units.count { i += 1 }
        return line
    }
    while i < units.count {
        let c = units[i]
        if spaces.contains(c) {
            i += 1
        } else if c == 37 && (i == 0 || units[i - 1] == 10) {
            _ = restOfLine() // Escaped line, for the exporter rather than us.
        } else if c == 91 {
            guard let header = headerAtStart(slice(i, units.count)) else {
                throw PgnFailure(message: "A header is not written [Name \"value\"]: \(restOfLine().trimmingCharacters(in: pgnWhitespace))")
            }
            tokens.append(.header(header.name, header.value))
            i += header.length
        } else if c == 123 {
            guard let end = units[(i + 1)...].firstIndex(of: 125) else {
                throw PgnFailure(message: "A comment is never closed")
            }
            tokens.append(.comment(slice(i + 1, end)))
            i = end + 1
        } else if c == 59 {
            i += 1
            tokens.append(.comment(restOfLine()))
        } else if c == 40 {
            tokens.append(.open); i += 1
        } else if c == 41 {
            tokens.append(.close); i += 1
        } else if c == 36 {
            i += 1
            let start = i
            while i < units.count && units[i] >= 48 && units[i] <= 57 { i += 1 }
            guard i > start, let nag = Int(slice(start, i)) else {
                throw PgnFailure(message: "A $ is not followed by a number")
            }
            tokens.append(.nag(nag))
        } else {
            let start = i
            while i < units.count && !spaces.contains(units[i]) && !punctuation.contains(units[i]) { i += 1 }
            guard start < i else {
                // The web's sticky word matcher fails here; report its error
                // instead of letting a malformed delimiter stall the reader.
                throw PgnFailure(message: "Cannot read properties of null (reading '0')")
            }
            tokens.append(contentsOf: wordTokens(slice(start, i)))
        }
    }
    return tokens
}

private func wordTokens(_ word: String) -> [PgnToken] {
    if RESULTS.contains(word) { return [.result(word)] }
    let rest = word.replacingOccurrences(of: #"^[0-9]+\.+"#, with: "", options: .regularExpression)
    if rest.isEmpty { return [] }
    if let nag = wordNags[rest] { return [.nag(nag)] }
    var san = rest
    var suffix = ""
    while suffix.count < 2, let c = san.last, c == "!" || c == "?" {
        suffix = String(c) + suffix
        san.removeLast()
    }
    if san.hasPrefix("0-0-0") { san = "O-O-O" + san.dropFirst(5) }
    else if san.hasPrefix("0-0") { san = "O-O" + san.dropFirst(3) }
    var tokens: [PgnToken] = [.move(san)]
    if let nag = suffixNags[suffix] { tokens.append(.nag(nag)) }
    return tokens
}

private func splitGames(_ tokens: [PgnToken]) -> [[PgnToken]] {
    var games: [[PgnToken]] = []
    var current: [PgnToken] = []
    var moved = false
    var depth = 0
    func close() {
        if !current.isEmpty { games.append(current) }
        current = []; moved = false; depth = 0
    }
    for token in tokens {
        if case .header = token, moved { close() }
        current.append(token)
        if case .header = token {} else { moved = true }
        if case .open = token { depth += 1 }
        if case .close = token { depth -= 1 }
        if case .result = token, depth <= 0 { close() }
    }
    close()
    return games
}

/// Collapse ECMAScript whitespace, not the wider Unicode whitespace set.
func cleanPgnText(_ text: String) -> String {
    text.components(separatedBy: pgnWhitespace).filter { !$0.isEmpty }.joined(separator: " ")
}
private func joinComment(_ held: String?, _ text: String) -> String? {
    let cleaned = cleanPgnText(text)
    guard !cleaned.isEmpty else { return held }
    return held.map { $0.isEmpty ? cleaned : $0 + " " + cleaned } ?? cleaned
}

/// Check SAN (or loose algebraic accepted by the web) only at the board boundary.
func playFrom(_ fen: String, _ move: String) throws -> MoveNode {
    guard let played = Board.playSan(fen, move) else {
        throw PgnFailure(message: "\(move) is not a legal move here")
    }
    return MoveNode(san: played.san, uci: played.uci, fen: played.fenAfter)
}

/// White always has a number; Black does after an interruption or line start.
func moveNumber(_ fenBefore: String, _ alwaysForBlack: Bool) -> String? {
    let fields = fenBefore.components(separatedBy: " ")
    let side = fields.count > 1 ? fields[1] : ""
    let full = fields.count > 5 ? fields[5] : "undefined"
    if side == "w" { return full + "." }
    return alwaysForBlack ? full + "..." : nil
}

private struct PgnReader {
    let tokens: [PgnToken]
    var i = 0
    var comment: String?
    var result: String?

    /// A variation is an alternative to the last move, from the position
    /// before it. It belongs to that move's sibling list, not its children.
    mutating func line(_ startFen: String, top: Bool) throws -> [MoveNode] {
        var moves: [MoveNode] = []
        var at: MovePath = []
        var last: (path: MovePath, parent: MovePath, fenBefore: String)?
        var before: String?
        var fen = startFen
        while i < tokens.count {
            let token = tokens[i]
            switch token {
            case .header:
                throw PgnFailure(message: "A header in the middle of the moves")
            case .comment(let text):
                if let last {
                    changeMoveList(&moves, at: last.parent) { list in
                        let index = last.path.last!
                        list[index].comment = joinComment(list[index].comment, text)
                    }
                } else if top { comment = joinComment(comment, text) }
                else { before = joinComment(before, text) }
            case .nag(let nag):
                guard let last else { throw PgnFailure(message: "An annotation before any move") }
                changeMoveList(&moves, at: last.parent) { $0[last.path.last!].nags.append(nag) }
            case .move(let san):
                var node: MoveNode
                do { node = try playFrom(fen, san) }
                catch { throw PgnFailure(message: "\(moveNumber(fen, true) ?? "null") \(san) is not a legal move") }
                node.before = before; before = nil
                var index = 0
                changeMoveList(&moves, at: at) { index = $0.count; $0.append(node) }
                last = (at + [index], at, fen)
                at = at + [index]
                fen = node.fen
            case .open:
                guard let last else { throw PgnFailure(message: "A variation before any move") }
                i += 1
                let alternatives = try line(last.fenBefore, top: false)
                changeMoveList(&moves, at: last.parent) { $0.append(contentsOf: alternatives) }
            case .close:
                if top { throw PgnFailure(message: "A ) with no ( before it") }
                return moves
            case .result(let value):
                if !top { throw PgnFailure(message: "A result inside a variation") }
                result = value
            }
            i += 1
        }
        if !top { throw PgnFailure(message: "A ( is never closed") }
        return moves
    }

    mutating func game() throws -> ParsedGame {
        var headers = PgnHeaders()
        while i < tokens.count {
            guard case .header(let name, let value) = tokens[i] else { break }
            headers[name] = value; i += 1
        }
        var startFen = Board.defaultPosition
        if let fen = headers["FEN"], !fen.isEmpty {
            let check = Board.validateFen(fen)
            guard check.ok else {
                throw PgnFailure(message: "The FEN header is not a position: \(check.error ?? "undefined")")
            }
            startFen = fen
        }
        let moves = try line(startFen, top: true)
        headers["Result"] = headers["Result"] ?? result ?? "*"
        return ParsedGame(headers: headers, startFen: startFen, comment: comment, moves: moves)
    }
}

/// Report and skip a broken game while retaining the rest of a file.
/// A bare FEN is a new game with no moves, for pasting a position on its own.
func parsePgnFile(_ text: String) -> PgnFile {
    let trimmed = text.trimmingCharacters(in: pgnWhitespace)
    if !trimmed.isEmpty, !trimmed.contains("\n"), Board.validateFen(trimmed).ok {
        return PgnFile(games: [newGame(trimmed)])
    }
    let tokens: [PgnToken]
    do { tokens = try tokenizePgn(trimmed) }
    catch { return PgnFile(errors: [PgnError(game: 1, message: String(describing: error))]) }
    var file = PgnFile()
    for (index, tokens) in splitGames(tokens).enumerated() {
        do {
            var reader = PgnReader(tokens: tokens)
            file.games.append(try reader.game())
        } catch { file.errors.append(PgnError(game: index + 1, message: String(describing: error))) }
    }
    return file
}

/// Stored PGN is known good; callers importing files use parsePgnFile instead.
func parsePgn(_ text: String) throws -> ParsedGame {
    let file = parsePgnFile(text)
    if let error = file.errors.first { throw PgnFailure(message: error.message) }
    return file.games.first ?? newGame()
}

/// Leading headers only, without reading moves for every game in a list.
func readHeaders(_ pgn: String) -> PgnHeaders {
    var headers = PgnHeaders()
    for line in pgn.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: pgnWhitespace)
        if trimmed.isEmpty {
            if !headers.names.isEmpty { break }
            continue
        }
        guard let header = headerAtStart(trimmed) else { break }
        headers[header.name] = header.value
    }
    return headers
}

func newGame(_ startFen: String = Board.defaultPosition) -> ParsedGame {
    var headers = PgnHeaders([
        ("Event", "?"), ("Site", "?"), ("Date", "????.??.??"), ("Round", "?"),
        ("White", "?"), ("Black", "?"), ("Result", "*"),
    ])
    if startFen != Board.defaultPosition {
        headers["SetUp"] = "1"; headers["FEN"] = startFen
    }
    return ParsedGame(headers: headers, startFen: startFen)
}

private func escapeHeader(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}
private func commentToken(_ text: String) -> String {
    "{" + text.replacingOccurrences(of: "}", with: ")") + "}"
}
/// JS counts UTF-16 units. Number and move remain one token during wrapping.
private func wrapPgn(_ tokens: [String]) -> String {
    var lines: [String] = []
    var current = ""
    for token in tokens {
        if !current.isEmpty && current.utf16.count + 1 + token.utf16.count > 80 {
            lines.append(current); current = token
        } else { current = current.isEmpty ? token : current + " " + token }
    }
    if !current.isEmpty { lines.append(current) }
    return lines.joined(separator: "\n")
}

/// Byte-compatible PGN, with roster headers first and other headers in order.
func writePgn(_ game: ParsedGame) -> String {
    let names = sevenTagRoster.filter { game.headers[$0] != nil }
        + game.headers.names.filter { !sevenTagRoster.contains($0) }
    let headers = names.map { "[\($0) \"\(escapeHeader(game.headers[$0]!))\"]" }
    var out: [String] = []
    var opening = false
    func push(_ token: String) { out.append(opening ? "(" + token : token); opening = false }
    func move(_ node: MoveNode, _ fen: String, _ numbered: Bool) {
        if let before = node.before, !before.isEmpty { push(commentToken(before)) }
        let number = moveNumber(fen, numbered || !(node.before ?? "").isEmpty)
        push(number.map { $0 + " " + node.san } ?? node.san)
        for nag in node.nags { push("$\(nag)") }
        if let comment = node.comment, !comment.isEmpty { push(commentToken(comment)) }
    }
    func line(_ initial: [MoveNode], _ initialFen: String, _ initialNumbered: Bool) {
        var list = initial; var fen = initialFen; var numbered = initialNumbered
        while let main = list.first {
            move(main, fen, numbered)
            numbered = !(main.comment ?? "").isEmpty
            for alternative in list.dropFirst() {
                opening = true
                move(alternative, fen, true)
                line(alternative.children, alternative.fen, !(alternative.comment ?? "").isEmpty)
                out[out.count - 1] += ")"
                numbered = true
            }
            fen = main.fen; list = main.children
        }
    }
    if let comment = game.comment, !comment.isEmpty { push(commentToken(comment)) }
    line(game.moves, game.startFen, true)
    push(game.headers["Result"] ?? "*")
    return headers.joined(separator: "\n") + "\n\n" + wrapPgn(out) + "\n"
}
