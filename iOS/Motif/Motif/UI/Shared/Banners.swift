import SwiftUI

struct OfflineBanner: View {
    @Environment(AppState.self) private var app
    var body: some View {
        if !app.store.online {
            Text("Offline" + (app.store.pending > 0 ? " · \(app.store.pending) to upload" : ""))
                .font(.footnote).frame(maxWidth: .infinity).padding(6).background(.thinMaterial, ignoresSafeAreaEdges: [])
                .accessibilityIdentifier("offline-banner")
        } else if case .error(let message) = app.store.status {
            Text("Couldn't reach the server: " + message).font(.footnote).foregroundStyle(.red).padding(6)
        }
    }
}
/// Install banners inside each navigation destination so they consume content
/// space below its bar rather than covering the bar from outside the stack.
private struct LibraryBanners: ViewModifier {
    @Environment(AppState.self) private var app
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                OfflineBanner()
                if let notice = app.notice { NoticeBanner(text: notice) { app.notice = nil } }
            }
        }
    }
}
extension View {
    func libraryBanners() -> some View { modifier(LibraryBanners()) }
}
struct NoticeBanner: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        Button(action: dismiss) { HStack { Text(text); Spacer(); Image(systemName: "xmark") }.font(.footnote).padding(10) }
            .buttonStyle(.plain).background(Color.motifAccent.opacity(0.15), ignoresSafeAreaEdges: []).accessibilityLabel(text + ". Dismiss")
    }
}
struct OfflineNote: View {
    @Environment(AppState.self) private var app
    var body: some View {
        if !app.store.online { Text("You're offline. Editing needs a connection; solving doesn't.").font(.footnote).foregroundStyle(.secondary) }
    }
}
