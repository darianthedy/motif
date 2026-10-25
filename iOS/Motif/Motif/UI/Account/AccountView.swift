import SwiftUI

struct AccountView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        Form {
            Section {
                LabeledContent("Signed in as", value: app.store.user?.email ?? "")
                LabeledContent("Sync", value: syncDescription)
            }
            if app.usingDevAccount { Text("No database is configured, so this library stays on this device.").foregroundStyle(.secondary).font(.footnote) }
            Section {
                Button("Sign out", role: .destructive) { Task { await app.signOut() } }.disabled(!app.store.online)
                OfflineNote()
            }
        }.navigationTitle("Account")
    }
    private var syncDescription: String {
        let n = app.store.pending, waiting = "\(n) \(n == 1 ? "result" : "results") waiting to upload"
        if !app.store.online { return n > 0 ? "Offline · " + waiting : "Offline" }
        switch app.store.status {
        case .syncing: return "Syncing…"
        case .error(let message): return "Couldn't reach the server: " + message
        case .idle: return n > 0 ? waiting : "Up to date"
        }
    }
}
