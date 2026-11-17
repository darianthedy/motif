import Foundation

/// Where a scan puzzle has got to (Puzzle flow). Feedback isn't a step: each step shows its own
/// once it's graded. v1 runs `lastMove` → `quickScan` → `move` → `done`; `targets`, `arrows` and
/// `finalCheck` come with S07 and S08.
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
