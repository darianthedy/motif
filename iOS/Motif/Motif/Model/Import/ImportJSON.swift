import Foundation
import CoreFoundation

/// A collection in file order, each puzzle once.
struct ImportGroup: Equatable, Codable, Sendable {
    var name: String?
    var puzzles: [PuzzleContent]
}

struct ImportRejection: Equatable, Codable, Sendable {
    var index: Int
    var reason: String
}

struct ImportResult: Equatable, Codable, Sendable {
    var groups: [ImportGroup] = []
    var rejected: [ImportRejection] = []
    /// Convenience for a single group.
    var collectionName: String? = nil
}

/// Accept a collection or an array of collections. A repeated puzzle stays
/// where it first appeared, with the last entry's metadata. Indices are
/// file-wide so rejected row numbers mean something in the original file.
func importJson(_ text: String) -> ImportResult {
    var result = ImportResult()
    let parsed: Any
    do {
        parsed = try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
    } catch {
        // Parser diagnostics belong to the platform; the stable user-facing
        // prefix and rejection index are shared with the web.
        result.rejected.append(ImportRejection(index: -1, reason: "Not valid JSON: \(error.localizedDescription)"))
        return result
    }
    let blocks = (parsed as? [Any]) ?? [parsed]
    var index = 0
    for block in blocks {
        let group = block as? [String: Any]
        guard let rawPuzzles = group?["puzzles"] as? [Any] else {
            result.rejected.append(ImportRejection(index: index, reason: "Missing a \"puzzles\" array"))
            continue
        }
        let name = group?["collection"] as? String
        var puzzles: [PuzzleContent] = []
        var positions: [String: Int] = [:]
        for raw in rawPuzzles {
            if let puzzle = parseEntry(raw, index, &result) {
                let key = contentKey(puzzle)
                if let position = positions[key] {
                    puzzles[position] = puzzle
                } else {
                    positions[key] = puzzles.count
                    puzzles.append(puzzle)
                }
            }
            index += 1
        }
        result.groups.append(ImportGroup(name: name, puzzles: puzzles))
    }
    if result.groups.count == 1 { result.collectionName = result.groups[0].name }
    return result
}

private func reject(_ index: Int, _ reason: String, _ result: inout ImportResult) {
    result.rejected.append(ImportRejection(index: index, reason: reason))
}

private func parseLine(_ raw: Any) -> [Uci]? {
    guard let items = raw as? [Any] else { return nil }
    var line: [Uci] = []
    for item in items {
        guard let text = item as? String, let move = parseUci(text) else { return nil }
        line.append(move)
    }
    return line
}

/// Validate at import, before an impossible answer can strand a solver.
private func parseEntry(_ value: Any, _ index: Int, _ result: inout ImportResult) -> PuzzleContent? {
    guard let raw = value as? [String: Any], let fen = raw["fen"] as? String,
          Board.isValidFen(fen) else {
        reject(index, "Malformed FEN", &result)
        return nil
    }
    var content = common(raw, fen)
    if let rawPlacement = raw["add_piece"], !(rawPlacement is NSNull) {
        if let lines = raw["solutions"] as? [Any], !lines.isEmpty {
            reject(index, "A missing-piece puzzle answers with a piece, so it can carry no solution", &result)
            return nil
        }
        guard let placement = parseAddPiece(rawPlacement, fen, index, &result) else { return nil }
        content.addPiece = placement
        return content
    }
    guard let rawLines = raw["solutions"] as? [Any], !rawLines.isEmpty else {
        reject(index, "Puzzle has no solution", &result)
        return nil
    }
    for rawLine in rawLines {
        guard let line = parseLine(rawLine), !line.isEmpty else {
            reject(index, "Solution contains a malformed move", &result)
            return nil
        }
        // Both parities are real: an even line ends on the forced reply.
        content.solutions.append(line)
    }
    if let illegal = Board.firstIllegalMove(fen, content.solutions) {
        reject(index, "Move \(illegal.move.text) is illegal at ply \(illegal.ply + 1)", &result)
        return nil
    }
    return content
}

/// JSON booleans bridge to NSNumber too, but are not JS numbers.
private func number(_ value: Any?) -> NSNumber? {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
    return value
}

/// JavaScript String(number) uses fixed notation from 1e-6 through below 1e21.
private func sourceNumberText(_ number: NSNumber) -> String {
    let value = number.doubleValue
    if value == 0 { return "0" }
    if value == .infinity { return "Infinity" }
    if value == -.infinity { return "-Infinity" }
    var text = String(value)
    if let e = text.firstIndex(of: "e") {
        var mantissa = String(text[..<e])
        if mantissa.hasSuffix(".0") { mantissa.removeLast(2) }
        let exponent = Int(text[text.index(after: e)...])!
        if exponent >= -6 && exponent < 21 {
            let negative = mantissa.hasPrefix("-")
            let unsigned = negative ? String(mantissa.dropFirst()) : mantissa
            let digits = unsigned.replacingOccurrences(of: ".", with: "")
            let decimal = (unsigned.firstIndex(of: ".").map { unsigned.distance(from: unsigned.startIndex, to: $0) } ?? unsigned.count) + exponent
            if decimal <= 0 {
                text = "0." + String(repeating: "0", count: -decimal) + digits
            } else if decimal >= digits.count {
                text = digits + String(repeating: "0", count: decimal - digits.count)
            } else {
                let split = digits.index(digits.startIndex, offsetBy: decimal)
                text = String(digits[..<split]) + "." + digits[split...]
            }
            if negative { text = "-" + text }
        } else {
            text = mantissa + "e" + (exponent >= 0 ? "+" : "") + String(exponent)
        }
    }
    if text.hasSuffix(".0") { text.removeLast(2) }
    return text
}

/// Common metadata keeps both puzzle kinds from drifting.
private func common(_ raw: [String: Any], _ fen: String) -> PuzzleContent {
    let sourceId = (raw["id"] as? String) ?? number(raw["id"]).map(sourceNumberText)
    return PuzzleContent(fen: fen, solutions: [],
                         tags: (raw["tags"] as? [Any])?.compactMap { $0 as? String } ?? [],
                         comment: raw["comment"] as? String, sourceId: sourceId,
                         rating: number(raw["rating"])?.doubleValue)
}

private func parseAddPiece(_ raw: Any, _ fen: String, _ index: Int,
                           _ result: inout ImportResult) -> Placement? {
    guard let text = raw as? String, let placement = parsePlacement(text) else {
        reject(index, "Malformed piece to add — write it FEN-style, like \"Ng6\" or \"ng6\"", &result)
        return nil
    }
    guard placement.type != .king else {
        reject(index, "A king cannot be added — there is already one", &result)
        return nil
    }
    guard Board.pieceAt(fen, placement.square) == nil else {
        reject(index, "Square \(placement.square) is not empty, so nothing can be added to it", &result)
        return nil
    }
    guard Board.withPiece(fen, placement) != nil else {
        reject(index, "\(placementText(placement)) does not make a legal position", &result)
        return nil
    }
    return placement
}
