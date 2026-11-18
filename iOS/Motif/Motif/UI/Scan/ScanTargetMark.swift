import Foundation

/// A mark the target step puts on a square: a colour on a piece or an empty king-zone square,
/// or a dot on an empty square (king-zone and fork squares look the same, as
/// `ScanGrader.gradeTargets` grades them).
enum ScanTargetMark: Equatable, Sendable {
    case red, orange, dot

    /// A tap on a piece goes orange → red → clear (orange, the more common target, takes one tap);
    /// on an empty square, orange → red → dot → clear (a king-zone square is coloured by its count,
    /// AdviceCabinet's rule; a fork or check square is a dot).
    static func next(after mark: ScanTargetMark?, piece: Bool) -> ScanTargetMark? {
        switch mark {
        case nil: return .orange
        case .orange: return .red
        case .red: return piece ? nil : .dot
        case .dot: return nil
        }
    }
}
