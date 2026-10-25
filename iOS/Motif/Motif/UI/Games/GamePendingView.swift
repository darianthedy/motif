import SwiftUI
/// The viewer is the immediately following P11 slice.
struct GamePendingView: View {
    @Environment(AppState.self) private var app
    let gameId: String
    var body: some View {
        if let game = app.store.library?.games.first(where: { $0.id == gameId }) {
            ContentUnavailableView(gameTitle(readHeaders(game.pgn)), systemImage: "checkerboard.rectangle", description: Text("Game saved. The board viewer follows in P11."))
        }
    }
}
