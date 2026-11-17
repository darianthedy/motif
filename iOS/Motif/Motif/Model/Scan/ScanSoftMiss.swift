import Foundation

/// Something short of right that doesn't fail the puzzle (Scoring).
enum ScanSoftMiss: String, Codable, CaseIterable, Sendable {
    /// Called Flag on a quiet position.
    case flaggedQuiet
    case quickScanMissed, targetsMissed, arrowsMissed
    /// Over the step's target time (`ScanTiming`).
    case quickScanSlow, targetsSlow, arrowsSlow, moveSlow
}
