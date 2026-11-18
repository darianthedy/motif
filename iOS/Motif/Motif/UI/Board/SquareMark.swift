import SwiftUI

/// A tint on a square. Each has a shape as well as a colour, always (§4: never colour alone).
enum SquareMark: Equatable, Sendable {
    /// Quick scan: violet tint plus a corner notch (not green, which is the found ring's).
    case quickScan
    /// A piece that loses material: filled red tint plus `exclamationmark` in the corner.
    case red
    /// A piece attacked as often as defended: orange outline (no fill) plus `equal` in the corner.
    case orange

    /// Read after the square's piece by VoiceOver.
    var accessibilityName: String {
        switch self {
        case .quickScan: "marked"
        case .red: "marked red, loses material"
        case .orange: "marked orange, attacked as often as defended"
        }
    }

    /// The tint under the piece, dimmed when the mark is carried from an earlier step. A carried
    /// quick-scan mark has no fill: dimmed violet reads as pink on a light square, too close to a
    /// red target's tint, so its notch alone shows it.
    func fill(faded: Bool) -> Color? {
        guard faded else { return fill }
        return self == .quickScan ? nil : fill.map { $0.opacity(0.45) }
    }

    /// The tint under the piece; the orange mark is an outline only.
    var fill: Color? {
        switch self {
        case .quickScan: BoardPalette.markHighlight.opacity(0.45)
        case .red: BoardPalette.markRed.opacity(0.45)
        case .orange: nil
        }
    }
}
