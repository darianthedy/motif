import SwiftUI

/// Form-sheet toolbar: ✕ cancels, a prominent ✓ confirms (disabled until valid).
private struct SheetToolbar: ViewModifier {
    let confirmTitle: String
    let confirmDisabled: Bool
    let confirmIdentifier: String?
    let cancel: () -> Void
    let confirm: () -> Void
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark", role: .cancel, action: cancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle, systemImage: "checkmark", action: confirm)
                    .buttonStyle(.glassProminent)
                    .disabled(confirmDisabled)
                    .accessibilityIdentifier(confirmIdentifier ?? "")
            }
        }
    }
}
extension View {
    /// `confirmTitle` is the ✓ button's accessibility label, e.g. "Add 24 Puzzles".
    func sheetToolbar(confirm confirmTitle: String, disabled: Bool = false, identifier: String? = nil,
                      onCancel cancel: @escaping () -> Void, onConfirm confirm: @escaping () -> Void) -> some View {
        modifier(SheetToolbar(confirmTitle: confirmTitle, confirmDisabled: disabled, confirmIdentifier: identifier, cancel: cancel, confirm: confirm))
    }
}
