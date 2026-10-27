import SwiftUI

/// The single offline status: a pill under the title. Edit controls disable themselves.
struct OfflinePill: View {
    @Environment(AppState.self) private var app
    var body: some View {
        if !app.store.online {
            let label = "Offline" + (app.store.pending > 0 ? " · \(countLabel(app.store.pending, "result")) waiting" : "")
            Text("\(Image(systemName: "wifi.slash")) \(label)")
                .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .padding(.vertical, 4)
                .accessibilityIdentifier("offline-banner")
        }
    }
}
/// Persistent until dismissed: errors must not slip away unread.
struct ErrorBanner: View {
    let text: String
    var dismiss: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).accessibilityHidden(true)
            Text(text).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button("Dismiss", systemImage: "xmark", action: dismiss).labelStyle(.iconOnly).font(.footnote.weight(.semibold))
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityIdentifier("error-dismiss")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular.tint(.red.opacity(0.12)), in: .rect(cornerRadius: 16))
        .padding(.horizontal).padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("error-banner")
    }
}
/// Install banners inside each navigation destination so they consume content
/// space below its bar rather than covering the bar from outside the stack.
private struct LibraryBanners: ViewModifier {
    @Environment(AppState.self) private var app
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    OfflinePill()
                    if app.store.online, case .error(let message) = app.store.status { ErrorBanner(text: "Couldn't reach the server: " + message) }
                    if let error = app.error { ErrorBanner(text: error) { app.error = nil } }
                }
            }
            .overlay(alignment: .bottom) {
                if let notice = app.notice { Toast(text: notice) { app.dismissNotice() }.padding(.bottom, 12) }
            }
            .animation(.snappy, value: app.notice)
            .animation(.snappy, value: app.error)
    }
}
extension View {
    func libraryBanners() -> some View { modifier(LibraryBanners()) }
}
