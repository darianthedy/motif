import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var app
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("auth-email")
                SecureField("Password", text: $password).textContentType(.password).accessibilityIdentifier("auth-password")
            } header: {
                header
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                            .accessibilityIdentifier("sign-in-error")
                    }
                    if app.usingDevAccount { Text("No database is configured, so any email and password will do. This library stays on this device.") }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { buttons }
        .animation(.snappy, value: error)
    }
    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 40, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .background(Color.motifAccentStrong.gradient, in: .rect(cornerRadius: 20))
                .accessibilityHidden(true)
            Text("Motif").font(.largeTitle.bold()).foregroundStyle(.primary)
            Text("Your chess puzzles and games, the same on every device.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            OfflinePill()
        }
        .textCase(nil)
        .frame(maxWidth: .infinity)
        .padding(.top, 48).padding(.bottom, 20)
    }
    private var buttons: some View {
        let disabled = !app.store.online || busy || email.isEmpty || password.isEmpty
        return VStack(spacing: 8) {
            Button { submit(false) } label: {
                Group {
                    if busy { ProgressView().accessibilityLabel("Signing In") } else { Text("Sign In") }
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).controlSize(.large)
            .accessibilityIdentifier("sign-in")
            Button("Create Account") { submit(true) }
                .controlSize(.large).padding(.vertical, 4)
                .accessibilityIdentifier("create-account")
        }
        .disabled(disabled)
        .padding(.horizontal, 20).padding(.bottom, 8)
    }
    private func submit(_ up: Bool) {
        busy = true; error = nil
        Task {
            do { try await app.store.signIn(email.trimmingCharacters(in: CharacterSet(charactersIn: Uci.whitespace)), password, signUp: up) }
            catch {
                self.error = error.localizedDescription
                AccessibilityNotification.Announcement(error.localizedDescription).post()
            }
            busy = false
        }
    }
}
