import SwiftUI

/// The Scan tab's Import sheet: the same sources and preview as the Puzzles one, for a scan file.
struct ScanImportView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = ScanImportModel()
    @State private var filePicker = false
    @State private var sourceError: String?
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                if !app.store.online {
                    OfflineNote(text: "You’re offline. Importing needs a connection.", identifier: "scan-import-offline")
                }
                Section {
                    Button("Choose File…", systemImage: "doc") { filePicker = true }
                    Button("Paste From Clipboard", systemImage: "doc.on.clipboard") { paste() }.accessibilityIdentifier("scan-import-paste")
                    TextEditor(text: $model.text).autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.asciiCapable)
                        .font(.system(.footnote, design: .monospaced)).frame(minHeight: 170).accessibilityIdentifier("scan-import-text")
                        .onChange(of: model.text) { model.parse() }
                } header: { Text("Source") } footer: {
                    if let sourceError { Label(sourceError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).accessibilityIdentifier("scan-import-source-error") }
                    else { Text("A scan puzzle file from Caïssa, or its text pasted above.") }
                }
                preview
            }
            .navigationTitle("Import Scan Puzzles").navigationBarTitleDisplayMode(.inline)
            .sheetToolbar(confirm: model.incoming > 0 ? "Add \(countLabel(model.incoming, "Puzzle"))" : "Add",
                          disabled: !app.store.online || model.incoming == 0 || model.busy, identifier: "scan-import-add",
                          onCancel: { dismiss() }, onConfirm: { Task { if await model.apply(app) { dismiss() } } })
            .scrollDismissesKeyboard(.interactively).editorKeyboard()
            .task {
                #if DEBUG
                if let text = CaptureSeed.importText { model.text = text; model.parse() }
                #endif
            }
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
            let batch = model.plan(app.store.library ?? Library())
            Section {
                if model.incoming > 0 {
                    Label { Text("\(countLabel(batch.added, "new puzzle")), \(batch.updated) to update") } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.motifAccentStrong)
                    }.accessibilityIdentifier("scan-import-ready")
                }
                if !result.rejected.isEmpty {
                    Label { Text("\(countLabel(result.rejected.count, "puzzle")) rejected") } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    ForEach(Array(result.rejected.enumerated()), id: \.offset) { _, reject in
                        Text((reject.index >= 0 ? "Puzzle \(reject.index + 1): " : "") + reject.reason).font(.footnote).foregroundStyle(.red)
                    }
                }
            } header: { Text("Found") } footer: {
                if model.incoming > 0 { Text("A puzzle already in the pool is updated and keeps its progress.") }
            }
        }
    }
}
