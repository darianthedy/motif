import SwiftUI

/// The toolbar avatar on both home screens; it opens the Account sheet.
struct AccountButton: View {
    @Environment(AppState.self) private var app
    var body: some View {
        Button { app.showingAccount = true } label: {
            AccountAvatar(email: app.store.user?.email ?? "", size: 30)
        }
        .accessibilityLabel("Account")
        .accessibilityIdentifier("account")
    }
}
struct AccountAvatar: View {
    let email: String
    let size: CGFloat
    var body: some View {
        Text(email.first.map { String($0).uppercased() } ?? "?")
            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.motifAccentStrong, in: .circle)
            .accessibilityHidden(true)
    }
}

struct AccountView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var resetting = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AccountAvatar(email: email, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: email).font(.headline).lineLimit(1).truncationMode(.middle)
                            Text("Signed in").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("account-email")
                }
                Section {
                    syncRow
                } header: { Text("Sync") } footer: {
                    if app.usingDevAccount { Text("No database is configured, so this library stays on this device.") }
                }
                Section {
                    Button("Reset Puzzle Progress…", role: .destructive) { resetting = true }
                        .disabled(!app.store.online || app.store.library?.attempts.isEmpty != false)
                        .accessibilityIdentifier("reset-progress")
                } header: { Text("Progress") } footer: {
                    Text("Forgets every attempt on every device: solved, mistakes and sessions in progress. Your puzzles and collections stay.")
                }
                Section {
                    Button("Sign Out", role: .destructive) { Task { await app.signOut() } }
                        .disabled(!app.store.online)
                        .accessibilityIdentifier("sign-out")
                } footer: {
                    if !app.store.online { Text("Signing out needs a connection.") }
                }
                Section {
                    Text("Evaluation by Stockfish, licensed under GPL-3.0")
                    Link(destination: URL(string: "https://github.com/official-stockfish/Stockfish")!) { Label("Stockfish Source", systemImage: "chevron.left.forwardslash.chevron.right") }
                        .accessibilityIdentifier("stockfish-source")
                    Link(destination: URL(string: "https://github.com/darianthedy/motif")!) { Label("Motif Source", systemImage: "chevron.left.forwardslash.chevron.right") }
                        .accessibilityIdentifier("motif-source")
                } header: { Text("Acknowledgements") } footer: {
                    Text(version).frame(maxWidth: .infinity).padding(.top, 8).accessibilityIdentifier("app-version")
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }.accessibilityIdentifier("account-close")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let error = app.error { ErrorBanner(text: error) { app.error = nil } }
            }
            .overlay(alignment: .bottom) {
                if let notice = app.notice { Toast(text: notice) { app.dismissNotice() }.padding(.bottom, 12) }
            }
            .animation(.snappy, value: app.notice)
            .animation(.snappy, value: app.error)
            .confirmationDialog("Reset puzzle progress?", isPresented: $resetting, titleVisibility: .visible) {
                Button("Reset Progress", role: .destructive) { Task { _ = await app.edit({ try await $0.resetProgress() }, done: "Progress reset. Every puzzle is unseen again.") } }
                    .accessibilityIdentifier("reset-confirm")
            } message: {
                Text("Forget every attempt? Your puzzles and collections stay. Solved, mistakes and in-progress sessions are cleared on every device.")
            }
        }
    }
    private var email: String { app.store.user?.email ?? "" }
    @ViewBuilder private var syncRow: some View {
        let n = app.store.pending, waiting = "\(countLabel(n, "result")) waiting"
        Group {
            if !app.store.online {
                Label(n > 0 ? "Offline · " + waiting : "Offline", systemImage: "wifi.slash").foregroundStyle(.secondary)
            } else {
                switch app.store.status {
                case .syncing:
                    Label { Text("Syncing…") } icon: { ProgressView() }
                case .error(let message):
                    Label { VStack(alignment: .leading, spacing: 2) { Text("Couldn't reach the server"); Text(message).font(.footnote).foregroundStyle(.secondary) } }
                        icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                case .idle:
                    if n > 0 { Label(waiting + " to upload", systemImage: "arrow.triangle.2.circlepath") }
                    else { Label { Text("Up to date") } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.motifAccentStrong) } }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sync-status")
    }
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?", build = info?["CFBundleVersion"] as? String ?? "?"
        return "Motif \(short) (\(build))"
    }
}
