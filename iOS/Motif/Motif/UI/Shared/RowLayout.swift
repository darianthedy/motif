import SwiftUI

/// A Settings-style icon tile that grows with Dynamic Type, so the symbol never outgrows its square.
struct IconTile: View {
    let systemImage: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 30
    var body: some View {
        Image(systemName: systemImage).font(.footnote.weight(.semibold)).foregroundStyle(.white)
            .frame(width: size, height: size).background(color, in: .rect(cornerRadius: size * 0.23))
            .accessibilityHidden(true)
    }
}
/// Side by side normally; stacked at accessibility text sizes, where a row has no room for both.
struct RowStack<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing / 2))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}
extension View {
    /// One line normally; wraps at accessibility text sizes instead of truncating to an ellipsis.
    func rowLineLimit() -> some View { modifier(RowLineLimit()) }
}
private struct RowLineLimit: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    func body(content: Content) -> some View { content.lineLimit(typeSize.isAccessibilitySize ? nil : 1) }
}
