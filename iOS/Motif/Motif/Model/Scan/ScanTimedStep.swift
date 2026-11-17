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
}
