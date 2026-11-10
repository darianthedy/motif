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
    /// The sheet's own visible size (the keyboard's safe area excluded), read once for the layout.
    @State private var size = CGSize.zero
    /// Sheets at least this wide put the preview beside the form (decision 21: IL, iPad).
    static let besideWidth: CGFloat = 600
    var body: some View {
        let check = model.fenCheck
        let beside = size.width >= Self.besideWidth
        // One `AnyLayout` (decision 21, F18), so the form, and the FEN draft and its focus with
        // it, keep their identity when a fold changes the sheet's width.
        let layout = beside ? AnyLayout(HStackLayout(alignment: .top, spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        NavigationStack {
            layout {
                if beside { preview(check).padding(16) }
                Form {
                    if !app.store.online {
                        // At the top, where it explains the disabled ✓ before anything else (F19).
                        Section {
                            Label("You’re offline. Adding games needs a connection.", systemImage: "wifi.slash")
                                .foregroundStyle(.motifSecondary)
                                // One element, so the identifier names the note rather than its text and icon apart.
                                .accessibilityElement(children: .combine).accessibilityIdentifier("game-new-offline")
                        }
                    }
                    Section {
                        Picker("Start From", selection: $fromFen) {
                            Text("Standard Start").tag(false)
                            Text("From a FEN").tag(true)
                        }
                        .pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                        .accessibilityIdentifier("game-start-mode")
                    } footer: {
                        if beside && !fromFen { sideToMove }
                    }
                    if !beside {
                        Section {
                            preview(check).frame(maxWidth: .infinity)
                                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        }
                    }
                    if fromFen {
                        Section {
                            TextField("FEN", text: $fen, prompt: motifPrompt("FEN"), axis: .vertical).font(.system(.footnote, design: .monospaced))
                                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                                .accessibilityIdentifier("game-start-fen")
                        } header: { Text("Starting Position") } footer: {
                            if !check.ok {
                                Label(check.error ?? "Invalid FEN", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                                    .accessibilityElement(children: .combine).accessibilityIdentifier("game-fen-error")
                            } else { sideToMove }
                        }
                    } else if !beside {
                        Section { } footer: { sideToMove }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
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
    /// Beside the form: the sheet's height less its padding, at most 42 % of the width (272 pt on IL).
    /// Stacked: at most 40 % of the visible sheet, so the FEN field and its error stay in view
    /// with the keyboard up (96 pt on the outer display).
    private var previewSide: CGFloat {
        guard size.width > 0, size.height > 0 else { return 0 }
        if size.width >= Self.besideWidth { return max(0, min(size.height - 32, size.width * 0.42)) }
        return max(0, min(size.width - 32, size.height * 0.4))
    }
    private func preview(_ check: Board.FenValidation) -> some View {
        BoardView(fen: shown, orientation: Board.turnOf(shown) ?? .white, interactive: false)
            .frame(width: previewSide, height: previewSide)
            .opacity(check.ok ? 1 : 0.4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(check.ok ? "Starting position preview" : "Preview unavailable: invalid FEN")
            .accessibilityIdentifier("game-new-preview")
    }
    @ViewBuilder private var sideToMove: some View {
        if let side = Board.turnOf(model.start) {
            Text("\(side == .white ? "White" : "Black") to move. The board faces the side to move.")
        }
    }
    private func sync() {
        model.fen = fromFen ? fen : ""
        if model.fenCheck.ok { shown = model.start }
    }
}
