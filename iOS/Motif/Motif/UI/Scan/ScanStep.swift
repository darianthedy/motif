import Foundation

/// Where a scan puzzle has got to (Puzzle flow). Feedback isn't a step: each step shows its own
/// once it's graded. `lastMove` → `quickScan` → `move` → `done`; a Flag call on a puzzle with a full
/// scan runs `arrows` (CCT, with ungraded target marks) before the move, and holds the move for
/// `finalCheck`.
enum ScanStep: Equatable, Sendable {
    case lastMove, quickScan, arrows, move, finalCheck, done

    /// The navigation title while the step is on screen.
    var title: String {
        switch self {
        case .lastMove: "Last Move"
        case .quickScan: "Quick Scan"
        case .arrows: "Checks, Captures, Threats"
        case .move: "Move"
        case .finalCheck: "Final Check"
        case .done: "Result"
        }
    }
}
