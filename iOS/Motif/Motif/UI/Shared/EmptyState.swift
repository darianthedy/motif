import SwiftUI

/// The one empty-list view: `ContentUnavailableView` with a main action and, rarely, a second one.
struct EmptyState: View {
    struct Action {
        var title: String
        var identifier: String?
        var disabled = false
        var perform: () -> Void
    }
    let title: String
    let systemImage: String
    var description: String?
    var action: Action?
    var secondary: Action?
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let description { Text(description) }
        } actions: {
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.glassProminent)
                    .disabled(action.disabled)
                    .accessibilityIdentifier(action.identifier ?? "")
            }
            if let secondary {
                Button(secondary.title, action: secondary.perform)
                    .buttonStyle(.glass)
                    .disabled(secondary.disabled)
                    .accessibilityIdentifier(secondary.identifier ?? "")
            }
        }
    }
}
