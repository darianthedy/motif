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
    @State private var model: ImportModel
    @State private var filePicker = false
    @State private var sourceError: String?
    /// `collectionId` preselects an existing collection ("Import Into Collection…").
    init(collectionId: String = "") {
        let model = ImportModel(); model.collectionId = collectionId
        _model = State(initialValue: model)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Choose File…", systemImage: "doc") { filePicker = true }
                    Button("Paste From Clipboard", systemImage: "doc.on.clipboard") { paste() }.accessibilityIdentifier("puzzle-import-paste")
                    TextEditor(text: $model.text).autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.asciiCapable).font(.system(.footnote, design: .monospaced)).frame(minHeight: 170).accessibilityIdentifier("puzzle-import-text")
                        .onChange(of: model.text) { model.parse() }
                } header: { Text("Source") } footer: {
                    if let sourceError { Label(sourceError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).accessibilityIdentifier("puzzle-import-source-error") }
                    else { Text("A JSON collection file, or its text pasted above.") }
                }
                preview
            }.navigationTitle("Import Puzzles").navigationBarTitleDisplayMode(.inline)
                .sheetToolbar(confirm: model.incoming > 0 ? "Add \(countLabel(model.incoming, "Puzzle"))" : "Add",
                              disabled: !app.store.online || model.incoming == 0 || model.busy, identifier: "puzzle-import-add",
                              onCancel: { dismiss() }, onConfirm: { Task { if await model.apply(app) { dismiss() } } })
                .scrollDismissesKeyboard(.interactively).editorKeyboard()
                .fileImporter(isPresented: $filePicker, allowedContentTypes: [.json]) { result in
                    do { model.text = try readImportFile(result.get()); model.parse(); sourceError = nil }
                    catch { sourceError = error.localizedDescription }
                }
        }
    }
    private func paste() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { sourceError = "The clipboard has no text to import."; return }
        model.text = text; model.parse(); sourceError = nil
    }
    @ViewBuilder private var preview: some View {
        if let result = model.result {
            Section("Found") {
                if model.incoming > 0 {
                    Label { Text("\(countLabel(model.incoming, "puzzle")) ready to add") } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.motifAccentStrong) }
                }
                if !result.rejected.isEmpty {
                    Label { Text("\(countLabel(result.rejected.count, "row")) rejected") } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    ForEach(Array(result.rejected.enumerated()), id: \.offset) { _, reject in
                        Text((reject.index >= 0 ? "Row \(reject.index + 1): " : "") + reject.reason).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            if model.incoming > 0 {
                Section {
                    if model.multi {
                        ForEach(Array(result.groups.enumerated()), id: \.offset) { _, group in
                            LabeledContent(group.name ?? "Imported", value: countLabel(group.puzzles.count, "puzzle"))
                        }
                    } else {
                        Picker("Collection", selection: $model.collectionId) {
                            Text("New Collection").tag("")
                            ForEach(collectionsOf(app.store.library ?? Library()), id: \.id) { Text($0.name).tag($0.id) }
                        }.pickerStyle(.menu)
                        if model.collectionId.isEmpty { TextField("Collection name", text: $model.name).accessibilityIdentifier("import-collection-name") }
                    }
                } header: { Text("Add to") } footer: { Text(addFooter) }
            }
        }
    }
    private var addFooter: String {
        if !app.store.online { return "You’re offline. Importing needs a connection." }
        if model.multi { return "Each collection in the file is added as a new collection." }
        return "Puzzles already in the collection are refreshed, not duplicated."
    }
}
func readImportFile(_ url: URL) throws -> String {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    return try String(contentsOf: url, encoding: .utf8)
}
