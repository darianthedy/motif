import Foundation

/// A mark the target step puts on a square: a colour on a piece, a dot on an empty square
/// (king-zone and fork squares look the same, as `ScanGrader.gradeTargets` grades them).
enum ScanTargetMark: Equatable, Sendable {
    case red, orange, dot

    /// A tap on a piece goes red → orange → clear; on an empty square, dot → clear.
    static func next(after mark: ScanTargetMark?, piece: Bool) -> ScanTargetMark? {
        guard piece else { return mark == nil ? .dot : nil }
        switch mark {
        case nil: return .red
        case .red: return .orange
        case .orange, .dot: return nil
        }
    }
}
