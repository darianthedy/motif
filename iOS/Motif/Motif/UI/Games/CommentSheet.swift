import SwiftUI
struct CommentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let online: Bool
    let save: (String) -> Void
    let textIdentifier: String
    let saveIdentifier: String
    @State private var text: String
    init(title: String, value: String?, online: Bool, textIdentifier: String = "game-comment-text", saveIdentifier: String = "game-comment-save",
         save: @escaping (String) -> Void) {
        self.title = title; self.online = online; self.save = save
        self.textIdentifier = textIdentifier; self.saveIdentifier = saveIdentifier; _text = State(initialValue: value ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(title) { TextEditor(text: $text).frame(minHeight: 150).accessibilityIdentifier(textIdentifier).disabled(!online) }
                if !text.isEmpty { Button("Remove Comment", role: .destructive) { save(""); dismiss() }.disabled(!online) }
            }.editorKeyboard().navigationTitle("Comment").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", systemImage: "checkmark") { save(text); dismiss() }.disabled(!online).accessibilityIdentifier(saveIdentifier) }
                }
        }.presentationDetents([.medium, .large])
    }
}
