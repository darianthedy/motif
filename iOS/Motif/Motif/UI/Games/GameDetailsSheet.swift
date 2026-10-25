import SwiftUI
let gameDetailFields: [(String, String)] = [("White", "White"), ("WhiteElo", "White rating"), ("Black", "Black"), ("BlackElo", "Black rating"), ("Event", "Event"), ("Site", "Site"), ("Date", "Date (YYYY.MM.DD)"), ("Round", "Round"), ("Opening", "Opening"), ("ECO", "ECO")]
struct GameDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let headers: PgnHeaders
    let online: Bool
    let save: (PgnHeaders) -> Void
    @State private var values: [String: String]
    init(headers: PgnHeaders, online: Bool, save: @escaping (PgnHeaders) -> Void) {
        self.headers = headers; self.online = online; self.save = save
        var initial = ["Result": headers["Result"] ?? "*"]
        for (key, _) in gameDetailFields { let value = headers[key] ?? ""; initial[key] = value.allSatisfy { $0 == "?" || $0 == "." } ? "" : value }
        _values = State(initialValue: initial)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(gameDetailFields, id: \.0) { key, label in
                        TextField(label, text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })).accessibilityIdentifier("game-header-" + key)
                    }
                    Picker("Result", selection: Binding(get: { values["Result"] ?? "*" }, set: { values["Result"] = $0 })) {
                        ForEach(RESULTS, id: \.self) { Text($0 == "*" ? "Unfinished or unknown" : $0).tag($0) }
                    }
                }.disabled(!online)
                OfflineNote()
            }.navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(changes); dismiss() }.disabled(!online) }
                }
        }
    }
    private var changes: PgnHeaders {
        let unknown = ["Event": "?", "Site": "?", "Date": "????.??.??", "Round": "?", "White": "?", "Black": "?"]
        var changes = PgnHeaders()
        for (key, _) in gameDetailFields + [("Result", "Result")] {
            let value = (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            changes[key] = value.isEmpty ? (headers[key] != nil ? unknown[key] ?? "" : "") : value
        }
        return changes
    }
}
