import SwiftUI
struct CommentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let online: Bool
    let save: (String) -> Void
    @State private var text: String
    init(title: String, value: String?, online: Bool, save: @escaping (String) -> Void) {
        self.title = title; self.online = online; self.save = save; _text = State(initialValue: value ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(title) { TextEditor(text: $text).frame(minHeight: 150).accessibilityIdentifier("game-comment-text").disabled(!online) }
                if !text.isEmpty { Button("Remove comment", role: .destructive) { save(""); dismiss() }.disabled(!online) }
            }.navigationTitle("Comment").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(text); dismiss() }.disabled(!online).accessibilityIdentifier("game-comment-save") }
                }
        }.presentationDetents([.medium, .large])
    }
}
