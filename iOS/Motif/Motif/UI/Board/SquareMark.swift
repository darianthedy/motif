import SwiftUI

/// A tint on a square. Each has a shape as well as a colour, always (§4: never colour alone).
enum SquareMark: Equatable, Sendable {
    /// Quick scan: a green ring round the piece, no fill. A violet tint blended with the
    /// last-move highlight (playtest 4); the ring reads on every square colour, and is the one the
    /// feedback draws for a square found.
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

    /// The tint under the piece, dimmed when the mark is carried from an earlier step.
    func fill(faded: Bool) -> Color? {
        guard faded else { return fill }
        return fill.map { $0.opacity(0.45) }
    }

    /// The tint under the piece; the quick-scan and orange marks are outlines only.
    var fill: Color? {
        switch self {
        case .quickScan: nil
        case .red: BoardPalette.markRed.opacity(0.45)
        case .orange: nil
        }
    }
}
