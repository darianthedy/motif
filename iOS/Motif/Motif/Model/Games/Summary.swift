import Foundation

/// PGN unknown values (?, ????.??.??) mean nothing known in a displayed list.
private func known(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: CharacterSet(charactersIn: Uci.whitespace)),
          !trimmed.isEmpty, trimmed.contains(where: { $0 != "?" && $0 != "." }) else { return nil }
    return trimmed
}
private func gameDate(_ value: String?) -> String? {
    var kept: [String] = []
    for part in (value ?? "").components(separatedBy: ".") {
        guard !part.isEmpty, part.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { break }
        kept.append(part)
    }
    return kept.isEmpty ? nil : kept.joined(separator: ".")
}
func gameTitle(_ headers: PgnHeaders) -> String {
    let white = known(headers["White"]), black = known(headers["Black"])
    if white != nil || black != nil { return "\(white ?? "?") – \(black ?? "?")" }
    return known(headers["Event"]) ?? "Untitled game"
}
func gameSubtitle(_ headers: PgnHeaders) -> String {
    let result = headers["Result"].flatMap { $0.isEmpty || $0 == "*" ? nil : $0 }
    let players = known(headers["White"]) != nil || known(headers["Black"]) != nil
    return [result, players ? known(headers["Event"]) : nil,
            known(headers["Opening"]) ?? known(headers["ECO"]), gameDate(headers["Date"])]
        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
}
/// Every query word must occur in the searchable headers; case is ignored.
func matchesSearch(_ headers: PgnHeaders, _ query: String) -> Bool {
    let words = query.lowercased().components(separatedBy: CharacterSet(charactersIn: Uci.whitespace))
        .filter { !$0.isEmpty }
    let searched = ["White", "Black", "Event", "Site", "Date", "Round", "Opening", "ECO", "Annotator"]
    let text = searched.map { headers[$0] ?? "" }.joined(separator: " ").lowercased()
    return words.allSatisfy { text.contains($0) }
}
/// Keep clock/eval commands in stored PGN, hide them only in displayed prose.
func displayComment(_ comment: String?) -> String {
    cleanPgnText((comment ?? "").replacingOccurrences(of: #"\[%[^\]]*\]"#, with: "", options: .regularExpression))
}
