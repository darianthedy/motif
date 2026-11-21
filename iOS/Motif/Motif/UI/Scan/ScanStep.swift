import Foundation

/// Where a scan puzzle has got to (Puzzle flow). Feedback isn't a step: each step shows its own
/// once it's graded. `lastMove` → `quickScan` → `move` → `done`; a Tactic call on a puzzle with a full
/// scan runs `arrows` (CCT, with ungraded target marks) before the move, and holds the move for
/// `finalCheck`. A first move on the puzzle's line (format v7) plays the `line` out before `done`.
enum ScanStep: Equatable, Sendable {
    case lastMove, quickScan, arrows, move, finalCheck, line, done

    /// The navigation title while the step is on screen.
    var title: String {
        switch self {
        case .lastMove: "Last Move"
        case .quickScan: "Quick Scan"
        case .arrows: "Checks, Captures, Threats"
        case .move: "Move"
        case .finalCheck: "Final Check"
        case .line: "Play the Line"
        case .done: "Result"
        }
    }
}
