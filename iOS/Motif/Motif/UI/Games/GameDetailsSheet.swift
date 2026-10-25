import SwiftUI
let gameDetailFields: [(String, String)] = [("White", "White"), ("WhiteElo", "White rating"), ("Black", "Black"), ("BlackElo", "Black rating"), ("Event", "Event"), ("Site", "Site"), ("Date", "Date"), ("Round", "Round"), ("Opening", "Opening"), ("ECO", "ECO")]
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
                Group {
                    Section("Players") { fields(["White", "WhiteElo", "Black", "BlackElo"]) }
                    Section("Result") {
                        Picker("Result", selection: Binding(get: { values["Result"] ?? "*" }, set: { values["Result"] = $0 })) {
                            ForEach(["1-0", "1/2-1/2", "0-1", "*"], id: \.self) { Text($0 == "1/2-1/2" ? "½-½" : $0).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("game-header-Result")
                    }
                    Section("Event") { fields(["Event", "Site", "Date", "Round"]) }
                    Section("Opening") { fields(["Opening", "ECO"]) }
                }.disabled(!online)
                OfflineNote()
            }.editorKeyboard().navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", systemImage: "checkmark") { save(changes); dismiss() }.disabled(!online) }
                }
        }
    }
    private func fields(_ keys: [String]) -> some View {
        ForEach(keys, id: \.self) { key in
            let label = gameDetailFields.first { $0.0 == key }?.1 ?? key, rating = key.hasSuffix("Elo")
            LabeledContent(rating ? "Rating" : label) {
                TextField(key == "Date" ? "YYYY.MM.DD" : rating ? "Unrated" : "Unknown", text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }))
                    .multilineTextAlignment(.trailing).keyboardType(rating ? .numberPad : .default).accessibilityLabel(label).accessibilityIdentifier("game-header-" + key)
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
