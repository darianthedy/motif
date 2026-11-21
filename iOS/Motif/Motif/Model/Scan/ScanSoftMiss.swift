import Foundation

/// Something short of right that doesn't fail the puzzle (Scoring).
enum ScanSoftMiss: String, Codable, CaseIterable, Sendable {
    /// Called Tactic on a quiet position.
    case flaggedQuiet
    case quickScanMissed, arrowsMissed
    /// Over the step's target time (`ScanTiming`).
    case quickScanSlow, arrowsSlow, moveSlow
    /// The target step's, on attempts from before v6 only: kept so they still read, never given now.
    case targetsMissed, targetsSlow

    /// Over a target time, not a miss of anything on the board.
    var isSlow: Bool { [.quickScanSlow, .targetsSlow, .arrowsSlow, .moveSlow].contains(self) }
}
