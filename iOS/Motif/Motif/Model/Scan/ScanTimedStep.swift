import Foundation

/// The steps with a target time (Puzzle flow).
enum ScanTimedStep: String, Codable, CaseIterable, Sendable {
    case quickScan
    /// The move after a No Flag call.
    case quietMove
    case targets, arrows
    /// The move and final check after a Flag call.
    case flaggedMove

    static func move(flagCall: Bool) -> ScanTimedStep { flagCall ? .flaggedMove : .quietMove }

    /// The move after `steps`: a full scan (run after a wrong No Flag too) makes it the flagged
    /// move, with its final check.
    static func move(flagCall: Bool, steps: ScanSteps) -> ScanTimedStep {
        move(flagCall: flagCall || steps.targets != nil)
    }
}
