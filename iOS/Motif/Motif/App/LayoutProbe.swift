import SwiftUI

// Temporary: iPhone Duo Phase 1. Compiled only with -DMOTIF_LAYOUT_PROBE, which the
// `layout_probe` TestFlight input and ios-duo-probe.yml set. Every other build gets
// the no-op below. Delete this file and its `.layoutProbe` calls after Phase 1.
#if MOTIF_LAYOUT_PROBE
import Combine

extension View {
    func layoutProbe(_ name: String, alignment: Alignment = .center) -> some View {
        overlay {
            GeometryReader { proxy in
                LayoutProbeHUD(name: name, proxy: proxy)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct LayoutProbeHUD: View {
    let name: String
    let proxy: GeometryProxy
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.verticalSizeClass) private var vertical
    @Environment(\.displayScale) private var scale
    @State private var keyboard = CGRect.zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(lines.joined(separator: "\n"))
            if #available(iOS 27.1, *) { ToolbarEdgeLine() }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.72), in: .rect(cornerRadius: 6))
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            keyboard = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
        }
    }

    private var lines: [String] {
        let insets = proxy.safeAreaInsets
        let frame = proxy.frame(in: .global)
        var out = [
            "[\(name)]",
            "safe \(pt(proxy.size.width))x\(pt(proxy.size.height)) at \(pt(frame.minX)),\(pt(frame.minY))",
            "insets T\(pt(insets.top)) L\(pt(insets.leading)) B\(pt(insets.bottom)) R\(pt(insets.trailing))",
            "full \(pt(proxy.size.width + insets.leading + insets.trailing))x\(pt(proxy.size.height + insets.top + insets.bottom))",
            "class w:\(label(horizontal)) h:\(label(vertical)) @\(pt(scale))x",
        ]
        if let scene = windowScene {
            let screen = scene.screen
            out.append("scene \(rect(scene.effectiveGeometry.coordinateSpace.bounds))")
            out.append("screen \(pt(screen.bounds.width))x\(pt(screen.bounds.height)) native \(pt(screen.nativeBounds.width))x\(pt(screen.nativeBounds.height)) @\(pt(screen.nativeScale))")
            out.append("orient \(scene.effectiveGeometry.interfaceOrientation.rawValue)")
        }
        if keyboard != .zero { out.append("kbd \(rect(keyboard))") }
        if #available(iOS 27.1, *) { out += regions }
        return out
    }
    @available(iOS 27.1, *)
    private var regions: [String] { region("div", .division) + region("occ", .occlusion) }
    @available(iOS 27.1, *)
    private func region(_ tag: String, _ kind: ReservedRegion.Kind) -> [String] {
        proxy.reservedRegions(kind: kind, options: .includeInactive, layoutDirectionBehavior: .fixed).map {
            "\(tag)\($0.isActive ? "+" : "-") \(rect($0.frame)) m\(pt($0.margins.top)),\(pt($0.margins.leading)),\(pt($0.margins.bottom)),\(pt($0.margins.trailing))"
        }
    }
    private var windowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
    private func label(_ size: UserInterfaceSizeClass?) -> String {
        switch size { case .compact: "C"; case .regular: "R"; default: "?" }
    }
}

/// A separate view because the environment value only exists on iOS 27.1.
@available(iOS 27.1, *)
private struct ToolbarEdgeLine: View {
    @Environment(\.toolbarVerticalEdge) private var edge
    var body: some View {
        Text("bar \(edge.map { $0 == .leading ? "leading" : "trailing" } ?? "horizontal")")
    }
}

private func pt(_ value: CGFloat) -> String { String(format: value == value.rounded() ? "%.0f" : "%.1f", value) }
private func rect(_ value: CGRect) -> String { "\(pt(value.minX)),\(pt(value.minY)) \(pt(value.width))x\(pt(value.height))" }
#else
extension View {
    func layoutProbe(_ name: String, alignment: Alignment = .center) -> some View { self }
}
#endif
