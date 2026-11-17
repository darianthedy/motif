import Foundation

/// The steps a scan went through; a step not reached is nil (a skip has none,
/// a No Flag call has no targets or arrows).
struct ScanSteps: Equatable, Codable, Sendable {
    var quickScan: ScanMarkStep?
    var targets: ScanMarkStep?
    /// Arrows as from + to squares, e.g. "f3g5".
    var arrows: ScanMarkStep?
    var move: ScanMoveStep?
}
