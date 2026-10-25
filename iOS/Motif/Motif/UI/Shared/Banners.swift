import SwiftUI

struct OfflineBanner: View {
    @Environment(AppState.self) private var app
    var body: some View {
        if !app.store.online {
            Text("Offline" + (app.store.pending > 0 ? " · \(app.store.pending) to upload" : ""))
                .font(.footnote).frame(maxWidth: .infinity).padding(6).background(.thinMaterial)
        } else if case .error(let message) = app.store.status {
            Text("Couldn't reach the server: " + message).font(.footnote).foregroundStyle(.red).padding(6)
        }
    }
}
struct NoticeBanner: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        Button(action: dismiss) { HStack { Text(text); Spacer(); Image(systemName: "xmark") }.font(.footnote).padding(10) }
            .buttonStyle(.plain).background(Color.motifAccent.opacity(0.15)).accessibilityLabel(text + ". Dismiss")
    }
}
struct OfflineNote: View {
    @Environment(AppState.self) private var app
    var body: some View {
        if !app.store.online { Text("You're offline. Editing needs a connection; solving doesn't.").font(.footnote).foregroundStyle(.secondary) }
    }
}
