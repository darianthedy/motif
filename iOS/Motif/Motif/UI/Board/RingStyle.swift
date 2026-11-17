import Foundation

/// Feedback on a square after a step is graded.
enum RingStyle: Equatable, Sendable {
    /// Found: green solid ring with `checkmark`.
    case correct
    /// In the answer but not marked: dashed ring.
    case missed
    /// Marked but not in the answer: grey ring with `xmark`.
    case extra

    var accessibilityName: String {
        switch self {
        case .correct: "correct"
        case .missed: "missed"
        case .extra: "not in the answer"
        }
    }
}
