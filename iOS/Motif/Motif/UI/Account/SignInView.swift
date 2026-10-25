import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var app
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Sign in to see your puzzles. Your library is private to your account and the same on every device.")
                        .foregroundStyle(.secondary)
                    if app.usingDevAccount { Text("No database is configured, so any email and password will do. This library stays on this device.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("auth-email")
                    SecureField("Password", text: $password).textContentType(.password).accessibilityIdentifier("auth-password")
                }
                Section {
                    Button(busy ? "Working…" : "Sign in") { submit(false) }.accessibilityIdentifier("sign-in")
                    Button("Create an account") { submit(true) }
                }.disabled(!app.store.online || busy || email.isEmpty || password.isEmpty)
                if !app.store.online { Text("You're offline. Signing in needs a connection.").foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Motif")
        }
    }
    private func submit(_ up: Bool) {
        busy = true; error = nil
        Task {
            do { try await app.store.signIn(email.trimmingCharacters(in: CharacterSet(charactersIn: Uci.whitespace)), password, signUp: up) }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
