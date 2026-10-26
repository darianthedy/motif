import SwiftUI

/// A transient success message: a glass capsule above the tab bar.
/// `AppState.showNotice` announces it to VoiceOver and clears it after ~3 s.
struct Toast: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        Button(action: dismiss) {
            Label(text, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityLabel(text)
        .accessibilityHint("Dismisses")
        .accessibilityIdentifier("toast")
    }
}
