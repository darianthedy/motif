import Foundation
import CoreFoundation

/// Reads and checks scan puzzles from the maker. Pure: the import sheet uses
/// `read(_:)` on a file, the loader uses `problem(_:)` on rows written straight
/// to the database, so both reject the same things for the same reasons.
/// `scripts/validate-external.ts --scan` mirrors these checks and messages.
enum ScanImport {
    /// The newest format version this app understands. Version 2 adds the full
    /// scan: a Flag puzzle must carry `targets` and `arrows`, and both are
    /// checked against the position (`fullScanProblem`). Version 1 files still
    /// import; their Flag puzzles skip the full scan.
    static let version = 2

    struct Result: Equatable, Sendable {
        /// File order, each puzzle once: a puzzle listed twice keeps its first
        /// place with the last entry's answer.
        var puzzles: [ScanPuzzleContent] = []
        /// Index into the file's `scan` array; -1 for the whole file.
        var rejected: [ImportRejection] = []
    }

    /// Reads `{"version": 2, "scan": [ ... ]}`.
    static func read(_ text: String) -> Result {
        var result = Result()
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
        } catch {
            result.rejected.append(.init(index: -1, reason: "Not valid JSON: \(error.localizedDescription)"))
            return result
        }
        guard let file = parsed as? [String: Any], let entries = file["scan"] as? [Any] else {
            result.rejected.append(.init(index: -1, reason: "Missing a \"scan\" array"))
            return result
        }
        guard let version = integer(file["version"]) else {
            result.rejected.append(.init(index: -1, reason: "Missing \"version\""))
            return result
        }
        if let problem = versionProblem(version) {
            result.rejected.append(.init(index: -1, reason: problem))
            return result
        }
        var positions: [String: Int] = [:]
        for (index, entry) in entries.enumerated() {
            let content: ScanPuzzleContent
            switch parse(entry, version: version) {
            case .failure(let failure):
                result.rejected.append(.init(index: index, reason: failure.reason))
                continue
            case .success(let parsed):
                content = parsed
            }
            if let problem = problem(content) {
                result.rejected.append(.init(index: index, reason: problem))
                continue
            }
            let key = content.contentKey
            if let position = positions[key] {
                result.puzzles[position] = content
            } else {
                positions[key] = result.puzzles.count
                result.puzzles.append(content)
            }
        }
        return result
    }

    /// Why a puzzle can't be played, or nil when it can. Checks it against the
    /// rules of chess: everything the grader relies on must hold.
    static func problem(_ content: ScanPuzzleContent) -> String? {
        if let problem = versionProblem(content.version) { return problem }
        guard Board.isValidFen(content.fenBefore) else { return "Malformed FEN" }
        guard let start = Board.applyUci(content.fenBefore, content.lastMove) else {
            return "Last move \(content.lastMove.text) is illegal"
        }
        let answer = content.answer

        var squares = answer.quickScan.map(\.square)
        squares += answer.targets?.allSquares ?? []
        squares += (answer.arrows ?? []).flatMap { [$0.from, $0.to] }
        if let bad = squares.first(where: { !isSquare($0) }) {
            return "Square \(bad) is not on the board"
        }
        for arrow in answer.arrows ?? [] where Board.pieceAt(start, arrow.from) == nil {
            return "Arrow \(arrow.from)-\(arrow.to) does not start on a piece"
        }
        if content.version >= 2, let problem = fullScanProblem(answer, start: start) { return problem }

        let legal = Board.legalUcis(start)
        guard !legal.isEmpty else { return "The solver has no legal move" }
        let legalTexts = Set(legal.map(\.text))
        for move in answer.moves.keys.sorted() where !legalTexts.contains(move) {
            return "Move \(move) is illegal"
        }
        let missing = legal.map(\.text).filter { answer.moves[$0] == nil }
        if !missing.isEmpty {
            return "Moves are missing \(missing.count) legal move\(missing.count == 1 ? "" : "s"): "
                + missing.prefix(5).joined(separator: ", ") + (missing.count > 5 ? ", …" : "")
        }
        if let negative = answer.moves.keys.sorted().first(where: { answer.moves[$0]! < 0 }) {
            return "Move \(negative) has a negative score"
        }
        guard answer.moves.values.contains(0) else { return "No move is scored 0 (the best)" }

        if let line = answer.bestLine,
           let illegal = Board.firstIllegalMove(start, [line]) {
            return "Best line move \(illegal.move.text) is illegal at ply \(illegal.ply + 1)"
        }
        return nil
    }

    /// A `scan_puzzles` row, written by the app or straight to the database:
    /// `answer` is the stored JSON object, read with the same rules as a file.
    static func stored(fenBefore: String, lastMove: String, answer: Any, version: Int,
                       source: String?, sourceId: String?) throws -> ScanPuzzleContent {
        guard var raw = answer as? [String: Any] else { throw DataFailure(message: "Answer is not an object") }
        raw["fenBefore"] = fenBefore
        raw["lastMove"] = lastMove
        raw["source"] = source ?? NSNull()
        raw["sourceId"] = sourceId ?? NSNull()
        if let problem = versionProblem(version) { throw DataFailure(message: problem) }
        switch parse(raw, version: version) {
        case .failure(let failure): throw DataFailure(message: failure.reason)
        case .success(let content):
            if let problem = problem(content) { throw DataFailure(message: problem) }
            return content
        }
    }

    /// The first four FEN fields and the move, so move counters don't matter.
    static func contentKey(fenBefore: String, lastMove: Uci) -> String {
        "\(normalizeFen(fenBefore))/\(lastMove.text)"
    }

    // MARK: The full scan (version 2)

    /// What a version 2 puzzle's full scan must hold, so every target and arrow
    /// the solver is graded against can be marked or drawn on the board. Version
    /// 1 content isn't held to it: rows already stored keep loading.
    private static func fullScanProblem(_ answer: ScanAnswer, start: String) -> String? {
        if answer.flagged {
            guard answer.targets != nil else { return #"Flag puzzle is missing "targets""# }
            guard answer.arrows != nil else { return #"Flag puzzle is missing "arrows""# }
        }
        if let targets = answer.targets {
            var seen = Set<String>()
            for square in targets.allSquares where !seen.insert(square).inserted {
                return "Target \(square) is listed twice"
            }
            // Requirements › Puzzle flow: "Empty squares only for king-zone and fork squares."
            for square in targets.red + targets.orange where Board.pieceAt(start, square) == nil {
                return "Red or orange target \(square) is not a piece"
            }
            for square in targets.kingZone + targets.fork where Board.pieceAt(start, square) != nil {
                return "King-zone or fork square \(square) is not empty"
            }
        }
        guard let arrows = answer.arrows, let solver = Board.turnOf(start) else { return nil }
        var lines = Set<String>()
        for arrow in arrows {
            let name = "\(arrow.from)-\(arrow.to)"
            guard lines.insert(arrow.line).inserted else { return "Arrow \(name) is listed twice" }
            guard let piece = Board.pieceAt(start, arrow.from) else {
                return "Arrow \(name) does not start on a piece"
            }
            // Arrows are coloured by side, so the side must be the piece's.
            let side: ScanArrow.Side = piece.color == solver ? .own : .theirs
            guard arrow.side == side else {
                return "Arrow \(name) is \"\(arrow.side.rawValue)\" but starts on "
                    + (side == .own ? "the solver's piece" : "the opponent's piece")
            }
            let sans = arrowSans(start, from: arrow.from, to: arrow.to)
            guard !sans.isEmpty else { return "Arrow \(name) is not a legal move" }
            switch arrow.kind {
            case .capture where !sans.contains(where: { $0.contains("x") }):
                return "Arrow \(name) is not a capture"
            case .check where !sans.contains(where: { $0.hasSuffix("+") || $0.hasSuffix("#") }):
                return "Arrow \(name) does not give check"
            default:
                break
            }
        }
        return nil
    }

    /// An arrow as moves, one move deep for either side: the SAN of each legal move from `from`
    /// to `to` of that piece if its side were to move ("Nxe4"; promotions once per piece). Empty
    /// when it isn't one, so the arrow step can refuse it as the import does.
    static func arrowSans(_ fen: String, from: String, to: String) -> [String] {
        guard let piece = Board.pieceAt(fen, from) else { return [] }
        let turned = withTurn(fen, piece.color)
        return Board.legalUcis(turned)
            .filter { moveFrom($0) == from && moveTo($0) == to }
            .compactMap { Board.sanFor(turned, $0) }
    }

    /// The position with `side` to move. Handing the move over drops the en
    /// passant square, which only the side to move could use.
    private static func withTurn(_ fen: String, _ side: Side) -> String {
        var fields = fen.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 4, fields[1] != side.rawValue else { return fen }
        fields[1] = side.rawValue
        fields[3] = "-"
        return fields.joined(separator: " ")
    }

    // MARK: Reading one entry

    private struct Failure: Error { let reason: String }

    private static func versionProblem(_ version: Int) -> String? {
        guard version >= 1 else { return "Unknown format version \(version)" }
        guard version <= Self.version else {
            return "Format version \(version) is newer than this app understands (\(Self.version))"
        }
        return nil
    }

    private static func parse(_ value: Any, version: Int) -> Swift.Result<ScanPuzzleContent, Failure> {
        func fail(_ reason: String) -> Swift.Result<ScanPuzzleContent, Failure> { .failure(Failure(reason: reason)) }

        guard let raw = value as? [String: Any] else { return fail("Not an object") }
        guard let fen = raw["fenBefore"] as? String else { return fail("Malformed FEN") }
        guard let lastText = raw["lastMove"] as? String else { return fail("Missing \"lastMove\"") }
        guard let lastMove = Uci.parse(lastText) else { return fail("Last move \(lastText) is malformed") }
        guard let flagged = raw["flagged"] as? Bool, isBool(raw["flagged"]) else {
            return fail("Missing \"flagged\"")
        }

        guard let rawScan = raw["quickScan"] as? [Any] else { return fail("Missing a \"quickScan\" array") }
        var quickScan: [ScanSquare] = []
        for item in rawScan {
            guard let item = item as? [String: Any], let square = item["square"] as? String else {
                return fail("Malformed quick-scan square")
            }
            guard let kindText = item["kind"] as? String, let kind = ScanSquare.Kind(rawValue: kindText) else {
                return fail("Unknown quick-scan kind for \(square)")
            }
            quickScan.append(.init(square: square, kind: kind))
        }

        var targets: ScanTargets?
        if let rawTargets = raw["targets"], !(rawTargets is NSNull) {
            guard let rawTargets = rawTargets as? [String: Any] else { return fail("Malformed \"targets\"") }
            func list(_ key: String) -> [String]? {
                guard let value = rawTargets[key], !(value is NSNull) else { return [] }
                guard let items = value as? [Any] else { return nil }
                let squares = items.compactMap { $0 as? String }
                return squares.count == items.count ? squares : nil
            }
            guard let red = list("red"), let orange = list("orange"),
                  let kingZone = list("kingZone"), let fork = list("fork") else {
                return fail("Malformed \"targets\"")
            }
            targets = ScanTargets(red: red, orange: orange, kingZone: kingZone, fork: fork)
        }

        var arrows: [ScanArrow]?
        if let rawArrows = raw["arrows"], !(rawArrows is NSNull) {
            guard let items = rawArrows as? [Any] else { return fail("Malformed \"arrows\"") }
            var parsed: [ScanArrow] = []
            for item in items {
                guard let item = item as? [String: Any],
                      let from = item["from"] as? String, let to = item["to"] as? String else {
                    return fail("Malformed arrow")
                }
                guard let side = (item["side"] as? String).flatMap(ScanArrow.Side.init(rawValue:)) else {
                    return fail("Unknown arrow side for \(from)-\(to)")
                }
                guard let kind = (item["kind"] as? String).flatMap(ScanArrow.Kind.init(rawValue:)) else {
                    return fail("Unknown arrow kind for \(from)-\(to)")
                }
                parsed.append(.init(from: from, to: to, side: side, kind: kind))
            }
            arrows = parsed
        }

        guard let rawMoves = raw["moves"] as? [String: Any] else { return fail("Missing a \"moves\" object") }
        var moves: [String: Int] = [:]
        for (text, score) in rawMoves {
            guard let move = Uci.parse(text) else { return fail("Move \(text) is malformed") }
            guard let cp = integer(score) else { return fail("Move \(text) has no whole-number score") }
            moves[move.text] = cp
        }

        var bestLine: [Uci]?
        if let rawLine = raw["bestLine"], !(rawLine is NSNull) {
            guard let items = rawLine as? [Any] else { return fail("Malformed \"bestLine\"") }
            let line = items.compactMap { ($0 as? String).flatMap(Uci.parse) }
            guard line.count == items.count else { return fail("Best line contains a malformed move") }
            bestLine = line
        }

        let answer = ScanAnswer(flagged: flagged, quickScan: quickScan, targets: targets,
                                arrows: arrows, moves: moves, bestLine: bestLine)
        return .success(ScanPuzzleContent(
            fenBefore: fen, lastMove: lastMove, answer: answer, version: version,
            source: label(raw["source"]), sourceId: label(raw["sourceId"])))
    }

    private static func isSquare(_ text: String) -> Bool {
        text.range(of: "^[a-h][1-8]$", options: .regularExpression) != nil
    }

    private static func isBool(_ value: Any?) -> Bool {
        guard let value = value as? NSNumber else { return false }
        return CFGetTypeID(value) == CFBooleanGetTypeID()
    }

    /// A JSON number with no fraction; booleans bridge to NSNumber but aren't numbers.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBool(number) else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, abs(double) < 1e15 else { return nil }
        return Int(double)
    }

    /// A label written as a string or a number, as `id` is for puzzles.
    private static func label(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = integer(value) { return String(number) }
        return nil
    }
}
