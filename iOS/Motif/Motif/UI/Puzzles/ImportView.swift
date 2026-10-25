import SwiftUI
import UniformTypeIdentifiers

struct PuzzleImportBatch: Sendable {
    var collections: [Collection] = []
    var puzzles: [NewPuzzle] = []
    var added = 0
    var description: String {
        let refreshed = puzzles.count - added
        if added > 0 && refreshed > 0 { return "Added \(added) \(added == 1 ? "puzzle" : "puzzles"), refreshed \(refreshed)." }
        if added > 0 { return "Added \(added) \(added == 1 ? "puzzle" : "puzzles")." }
        if refreshed > 0 { return "No new puzzles — refreshed \(refreshed) you already had." }
        return "Nothing to add."
    }
}
@Observable @MainActor final class ImportModel {
    var text = ""
    var name = ""
    var collectionId = ""
    var busy = false
    private(set) var result: ImportResult?
    var incoming: Int { result?.groups.reduce(0) { $0 + $1.puzzles.count } ?? 0 }
    var multi: Bool { (result?.groups.count ?? 0) > 1 }
    func parse() {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: Uci.whitespace))
        result = trimmed.isEmpty ? nil : importJson(trimmed)
        if name.isEmpty { name = result?.collectionName ?? "" }
    }
    func plan(_ library: Library, now: Int64 = epochMilliseconds()) -> PuzzleImportBatch {
        var batch = PuzzleImportBatch()
        for group in result?.groups ?? [] where !group.puzzles.isEmpty {
            let id: String
            if !multi && !collectionId.isEmpty { id = collectionId }
            else {
                id = newID()
                let chosen = name.trimmingCharacters(in: CharacterSet(charactersIn: Uci.whitespace))
                batch.collections.append(Collection(id: id, name: !multi && !chosen.isEmpty ? chosen : group.name ?? "Imported", createdAt: now + Int64(batch.collections.count)))
            }
            let planned = planImport(puzzlesIn(library, id), group.puzzles, id)
            batch.puzzles += planned.puzzles; batch.added += planned.added
        }
        return batch
    }
    func apply(_ app: AppState) async -> Bool {
        guard app.store.online, let library = app.store.library, incoming > 0, !busy else { return false }
        busy = true; defer { busy = false }
        let batch = plan(library)
        return await app.edit({ backend in
            try await backend.createCollections(batch.collections)
            _ = try await backend.importPuzzles(batch.puzzles)
        }, done: batch.description)
    }
}
struct ImportView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = ImportModel()
    @State private var filePicker = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Choose a JSON collection file, or paste one") {
                    Button("Choose a file") { filePicker = true }
                    TextEditor(text: $model.text).font(.system(.footnote, design: .monospaced)).frame(minHeight: 170).accessibilityIdentifier("puzzle-import-text")
                        .onChange(of: model.text) { model.parse() }
                }
                preview
                OfflineNote()
            }.navigationTitle("Import puzzles").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .scrollDismissesKeyboard(.interactively)
                .fileImporter(isPresented: $filePicker, allowedContentTypes: [.json]) { result in
                    do { model.text = try readImportFile(result.get()); model.parse() }
                    catch { app.notice = error.localizedDescription }
                }
        }
    }
    @ViewBuilder private var preview: some View {
        if let result = model.result {
            Section {
                Text("\(model.incoming) puzzles read\(result.rejected.isEmpty ? "" : " · \(result.rejected.count) rejected")")
                ForEach(Array(result.rejected.enumerated()), id: \.offset) { _, reject in
                    Text((reject.index >= 0 ? "row \(reject.index + 1): " : "") + reject.reason).font(.footnote).foregroundStyle(.red)
                }
            }
            Section("Add to") {
                if model.multi {
                    ForEach(Array(result.groups.enumerated()), id: \.offset) { _, group in Text("\(group.name ?? "Imported") · \(group.puzzles.count) puzzles") }
                } else {
                    Picker("Collection", selection: $model.collectionId) {
                        Text("A new collection").tag("")
                        ForEach(collectionsOf(app.store.library ?? Library()), id: \.id) { Text($0.name).tag($0.id) }
                    }
                    if model.collectionId.isEmpty { TextField("Collection name", text: $model.name).accessibilityIdentifier("import-collection-name") }
                }
                Button(model.busy ? "Adding…" : "Add \(model.incoming) puzzles") {
                    Task { if await model.apply(app) { dismiss() } }
                }.disabled(!app.store.online || model.incoming == 0 || model.busy).accessibilityIdentifier("puzzle-import-add")
            }
        }
    }
}
func readImportFile(_ url: URL) throws -> String {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    return try String(contentsOf: url, encoding: .utf8)
}
