import Foundation

/// Where a scan puzzle has got to (Puzzle flow). Feedback isn't a step: each step shows its own
/// once it's graded. `lastMove` → `quickScan` → `move` → `done`; a Flag call on a puzzle with a full
/// scan runs `targets` → `arrows` before the move. `finalCheck` comes with S08.
enum ScanStep: Equatable, Sendable {
    case lastMove, quickScan, targets, arrows, move, finalCheck, done

    /// The navigation title while the step is on screen.
    var title: String {
        switch self {
        case .lastMove: "Last Move"
        case .quickScan: "Quick Scan"
        case .targets: "Targets"
        case .arrows: "Checks, Captures, Threats"
        case .move: "Move"
        case .finalCheck: "Final Check"
        case .done: "Result"
        }
    }
}
