import SwiftUI
import UniformTypeIdentifiers

extension UTType { static let chessPGN = UTType(filenameExtension: "pgn") ?? .plainText }
struct PGNExport: Transferable, Sendable {
    var text: String
    var name: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .chessPGN) { item in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Motif-export-" + newID())
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(pgnFileName(item.name))
            try Data(item.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
func pgnFileName(_ name: String) -> String {
    let safe = name.replacingOccurrences(of: #"[\\/:*?"<>|]+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    return (safe.isEmpty ? "games" : safe) + ".pgn"
}
func gamesAsFile(_ games: [Game]) -> String {
    games.map { game in
        var text = game.pgn
        while let scalar = text.unicodeScalars.last, CharacterSet(charactersIn: Uci.whitespace).contains(scalar) { text.removeLast() }
        return text
    }.joined(separator: "\n\n") + "\n"
}
