import Foundation

/// The steps a scan went through; a step not reached is nil (a skip has none,
/// a No Flag call has no arrows).
struct ScanSteps: Equatable, Codable, Sendable {
    var quickScan: ScanMarkStep?
    /// The graded target step of attempts from before v6, kept so they still read. Never written now.
    var targets: ScanMarkStep?
    /// Arrows as from + to squares, e.g. "f3g5".
    var arrows: ScanMarkStep?
    var move: ScanMoveStep?
}
