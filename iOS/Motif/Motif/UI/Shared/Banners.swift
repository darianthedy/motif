import SwiftUI

/// The width every transient banner and toast stops at (Duo plan decision 22).
let transientBannerWidth: CGFloat = 480

/// The single offline status: a pill trailing the title. Edit controls disable themselves.
struct OfflinePill: View {
    @Environment(AppState.self) private var app
    var body: some View {
        if !app.store.online {
            let label = "Offline" + (app.store.pending > 0 ? " · \(countLabel(app.store.pending, "result")) waiting" : "")
            Text("\(Image(systemName: "wifi.slash")) \(label)")
                .font(.footnote.weight(.medium)).foregroundStyle(.motifSecondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .motifGlass(in: .capsule)
                .padding(.vertical, 4)
                .accessibilityIdentifier("offline-banner")
        }
    }
}
/// Persistent until dismissed: errors must not slip away unread. A glass capsule at the
/// bottom of the content, ≤ 480 pt (decision 22).
struct ErrorBanner: View {
    let text: String
    var dismiss: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).accessibilityHidden(true)
            Text(text).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button("Dismiss", systemImage: "xmark", action: dismiss).labelStyle(.iconOnly).font(.footnote.weight(.semibold))
                    .buttonStyle(.plain).foregroundStyle(.motifSecondary).accessibilityIdentifier("error-dismiss")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .motifGlass(tint: .red.opacity(0.12), in: .rect(cornerRadius: 22))
        .frame(maxWidth: transientBannerWidth)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("error-banner")
    }
}
/// Persistent status (Offline, Offline · N waiting) on one screen: the pill at the trailing
/// edge, just under the title, so it never covers the bar or the content (decision 22).
/// Each navigation destination installs it, so it follows the screen that has the title.
private struct LibraryStatus: ViewModifier {
    @Environment(AppState.self) private var app
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if !app.store.online {
                OfflinePill().frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal)
            }
        }
    }
}
/// Transient messages (server errors, dismissible errors, the toast): glass capsules ≤ 480 pt,
/// centred at the bottom of the content via `.safeAreaInset(edge: .bottom)`, so they take
/// content space above the tab bar or the bottom bar and never sit over a board (decision 22,
/// F24–F26). Install once per window-sized container (the tab's split view, a session, a
/// sheet) so a two-column split shows one capsule, not one per column.
private struct LibraryMessages: ViewModifier {
    @Environment(AppState.self) private var app
    /// Off where the screen already shows the sync error itself (launch, Account's sync row).
    let serverStatus: Bool
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if serverStatus, app.store.online, case .error(let message) = app.store.status {
                        ErrorBanner(text: "Couldn't reach the server: " + message)
                    }
                    if let error = app.error { ErrorBanner(text: error) { app.error = nil } }
                    if let notice = app.notice { Toast(text: notice) { app.dismissNotice() } }
                }
                .padding(.horizontal)
                .padding(.bottom, hasMessage ? 8 : 0)
                .frame(maxWidth: .infinity)
            }
            .animation(.snappy, value: app.notice)
            .animation(.snappy, value: app.error)
    }
    private var hasMessage: Bool {
        if app.notice != nil || app.error != nil { return true }
        if serverStatus, app.store.online, case .error = app.store.status { return true }
        return false
    }
}
extension View {
    /// The offline pill under this screen's title. Use on each column and navigation destination.
    func libraryStatus() -> some View { modifier(LibraryStatus()) }
    /// The bottom capsule for errors and toasts. Use once around a window-sized container.
    func libraryMessages(serverStatus: Bool = true) -> some View { modifier(LibraryMessages(serverStatus: serverStatus)) }
}
