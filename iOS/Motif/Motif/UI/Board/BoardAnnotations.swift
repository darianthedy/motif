import Foundation

/// Everything drawn over the squares: one `Canvas` pass (`BoardOverlay`), plus the ghost in
/// the squares layer. `Equatable`, so Observation skips equal writes.
struct BoardAnnotations: Equatable, Sendable {
    /// Quick-scan highlight, red, orange.
    var tints: [String: SquareMark] = [:]
    /// King-zone and fork squares.
    var dots: Set<String> = []
    /// Feedback: correct, missed, extra.
    var rings: [String: RingStyle] = [:]
    var arrows: [BoardArrow] = []
    var ghost: BoardGhost?
    /// Squares whose tint or dot an earlier step left: drawn dimmed and read-only, so the targets
    /// build on the quick scan and the arrows on the targets.
    var faded: Set<String> = []

    var isEmpty: Bool { self == BoardAnnotations() }

    /// The marks on `square` for its VoiceOver label ("marked red, loses material, correct"),
    /// or nil when it has none. Arrows are listed below the board instead (S07).
    func accessibilityDescription(_ square: String) -> String? {
        var parts: [String] = []
        if let tint = tints[square] { parts.append(tint.accessibilityName) }
        if dots.contains(square) { parts.append("dot") }
        if !parts.isEmpty, faded.contains(square) { parts.append("from the step before") }
        if let ghost, ghost.square == square { parts.append("\(ghost.piece.color == .white ? "White" : "Black") \(ghost.piece.type.name) to play here") }
        if let ring = rings[square] { parts.append(ring.accessibilityName) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
