import Foundation

/// A square the quick scan should find, and why: used in the feedback reason.
struct ScanSquare: Hashable, Codable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// Newly attacked from the last move's to-square.
        case attacked
        /// On a line opened through the last move's from-square.
        case opened
        /// No longer defended after the last move.
        case undefended
        /// The solver's piece the opponent can now profitably capture, though it couldn't before
        /// the last move (v4): a broken pin or a removed counter-tactic. Tapped like the others.
        case unpinned
        /// The opponent's piece the solver can now win, though taking it lost material (or was
        /// impossible) before the last move (v5): the mirror of `unpinned`, e.g. a defender pinned
        /// to its own queen. The piece that just moved can be one. Tapped like the others.
        case hanging

        /// The kind as the app names it ("Unpinned").
        var label: String { rawValue.capitalized }
    }

    var square: String
    var kind: Kind
}
