import Foundation

/// Something short of right that doesn't fail the puzzle (Scoring).
enum ScanSoftMiss: String, Codable, CaseIterable, Sendable {
    /// Called Flag on a quiet position.
    case flaggedQuiet
    case quickScanMissed, targetsMissed, arrowsMissed
    /// Over the step's target time (`ScanTiming`).
    case quickScanSlow, targetsSlow, arrowsSlow, moveSlow

    /// Over a target time, not a miss of anything on the board.
    var isSlow: Bool { [.quickScanSlow, .targetsSlow, .arrowsSlow, .moveSlow].contains(self) }
}
