import SwiftUI

/// Standard start or a FEN, previewed live on the board; ✓ opens the new game in the viewer.
struct NewGameView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let collectionId: String
    @State private var model = AddGamesModel()
    @State private var fromFen = false
    @State private var fen = ""
    /// The last position that parsed, kept on the board (dimmed) while the FEN is invalid.
    @State private var shown = Board.defaultPosition
    var body: some View {
        let check = model.fenCheck
        NavigationStack {
            Form {
                Section {
                    Picker("Start From", selection: $fromFen) {
                        Text("Standard Start").tag(false)
                        Text("From a FEN").tag(true)
                    }
                    .pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("game-start-mode")
                }
                Section {
                    BoardView(fen: shown, orientation: Board.turnOf(shown) ?? .white, interactive: false)
                        .opacity(check.ok ? 1 : 0.4)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(check.ok ? "Starting position preview" : "Preview unavailable: invalid FEN")
                }
                if fromFen {
                    Section {
                        TextField("FEN", text: $fen, axis: .vertical).font(.system(.footnote, design: .monospaced))
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                            .accessibilityIdentifier("game-start-fen")
                    } header: { Text("Starting Position") } footer: {
                        if !check.ok {
                            Label(check.error ?? "Invalid FEN", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                                .accessibilityIdentifier("game-fen-error")
                        } else if let side = Board.turnOf(model.start) {
                            Text("\(side == .white ? "White" : "Black") to move. The board faces the side to move.")
                        }
                    }
                }
                if !app.store.online { Section { } footer: { Text("You’re offline. Adding games needs a connection.") } }
            }
            .navigationTitle("New Game").navigationBarTitleDisplayMode(.inline)
            .sheetToolbar(confirm: "Create Game", disabled: !check.ok || !app.store.online || model.busy, identifier: "game-new-board",
                          onCancel: { dismiss() }) {
                Task {
                    if let id = await model.add(app, collectionId: collectionId, newBoard: true) {
                        dismiss(); app.gamesPath.append(.game(collectionId, id))
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively).editorKeyboard()
            .onChange(of: fromFen) { sync() }
            .onChange(of: fen) { sync() }
        }
    }
    private func sync() {
        model.fen = fromFen ? fen : ""
        if model.fenCheck.ok { shown = model.start }
    }
}
