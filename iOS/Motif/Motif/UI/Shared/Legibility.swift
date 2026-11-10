import SwiftUI
import UIKit

/// Secondary text and glass that stay legible in every system variant (plan D10, §6.11–6.12).

extension Color {
    /// Secondary text at ≥ 4.5:1 in light and dark (F35). The system's `secondaryLabel` is
    /// 60 % gray: about 3.5:1 on white and 3.1:1 on the grouped gray in light mode. This is
    /// opaque, so it measures the same on glass and on grouped backgrounds:
    /// light #636366 (6.0:1 on white, 5.4:1 on #F2F2F7), dark #AEAEB2 (9.4:1 on black,
    /// 6.3:1 on #2C2C2E), and a step stronger with Increase Contrast.
    static let motifSecondaryText = Color(UIColor { traits in
        let high = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return high ? UIColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1) : UIColor(red: 0.68, green: 0.68, blue: 0.70, alpha: 1)
        }
        return high ? UIColor(red: 0.28, green: 0.28, blue: 0.29, alpha: 1) : UIColor(red: 0.39, green: 0.39, blue: 0.40, alpha: 1)
    })
}
extension ShapeStyle where Self == Color {
    /// `foregroundStyle(.motifSecondary)`: secondary text that keeps 4.5:1 (F35).
    static var motifSecondary: Color { .motifSecondaryText }
}
/// A text field's placeholder in the secondary text color (F35): the system's placeholder
/// gray is about 2:1. Pass it as the field's `prompt`.
func motifPrompt(_ text: String) -> Text { Text(text).foregroundStyle(.motifSecondary) }

private struct MotifReduceTransparencyKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Forces the Reduce Transparency fallback (the capture fixture `reduce-transparency`), since
    /// UI tests can't switch the system setting. `accessibilityReduceTransparency` is read too.
    var motifReduceTransparency: Bool {
        get { self[MotifReduceTransparencyKey.self] }
        set { self[MotifReduceTransparencyKey.self] = newValue }
    }
}
/// Liquid Glass on Motif's own controls and capsules (§6.12). With Reduce Transparency it
/// falls back to an opaque fill (`tertiarySystemBackground`, as the canvases' RT frames draw
/// it) with a hairline edge, so the capsule still reads against the board or the list behind
/// it; a tint becomes a solid fill. Increase Contrast adds a stronger edge in both cases.
private struct MotifGlass<S: Shape>: ViewModifier {
    let tint: Color?
    let interactive: Bool
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var systemReduce
    @Environment(\.motifReduceTransparency) private var forcedReduce
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        if systemReduce || forcedReduce {
            content
                .background {
                    ZStack {
                        shape.fill(Color(.tertiarySystemBackground))
                        if let tint { shape.fill(tint) }
                    }
                }
                .overlay { edge }
        } else {
            content
                .glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
                .overlay { if contrast == .increased { edge } }
        }
    }
    private var edge: some View {
        shape.stroke(contrast == .increased ? Color.primary.opacity(0.6) : Color(.separator), lineWidth: contrast == .increased ? 1 : 0.5)
            .allowsHitTesting(false)
    }
}
extension View {
    /// `glassEffect` with a legible fallback for Reduce Transparency and Increase Contrast.
    /// Use on Motif's own capsules and chips; system bars and `.glass` button styles adapt by themselves.
    func motifGlass<S: Shape>(tint: Color? = nil, interactive: Bool = false, in shape: S) -> some View {
        modifier(MotifGlass(tint: tint, interactive: interactive, shape: shape))
    }
}
