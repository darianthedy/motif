import Foundation

/// A mark the target step puts on a square: a colour on a piece, a dot on an empty square
/// (king-zone and fork squares look the same, as `ScanGrader.gradeTargets` grades them).
enum ScanTargetMark: Equatable, Sendable {
    case red, orange, dot

    /// A tap on a piece goes orange → red → clear (orange, the more common target, takes one tap);
    /// on an empty square, dot → clear.
    static func next(after mark: ScanTargetMark?, piece: Bool) -> ScanTargetMark? {
        guard piece else { return mark == nil ? .dot : nil }
        switch mark {
        case nil: return .orange
        case .orange: return .red
        case .red, .dot: return nil
        }
    }
}
