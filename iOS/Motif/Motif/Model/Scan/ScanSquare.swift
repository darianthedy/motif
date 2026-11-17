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
    }

    var square: String
    var kind: Kind
}
