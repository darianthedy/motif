import Foundation

/// What a scan can miss, by the maker's own labels (Scan plan §8): a quick-scan square's kind,
/// a target's list, an arrow's kind.
enum ScanMissCategory: Hashable, Sendable, CaseIterable {
    case quickScan(ScanSquare.Kind)
    case target(Target)
    case arrow(ScanArrow.Kind)

    /// The four target lists of `ScanTargets`.
    enum Target: String, CaseIterable, Sendable { case red, orange, kingZone, fork }

    static var allCases: [ScanMissCategory] {
        ScanSquare.Kind.allCases.map(Self.quickScan) + Target.allCases.map(Self.target) + ScanArrow.Kind.allCases.map(Self.arrow)
    }

    /// "Undefended squares", "Red targets", "Their captures" style names, for the screen and the export.
    var title: String {
        switch self {
        case .quickScan(.attacked): "Attacked squares"
        case .quickScan(.opened): "Opened lines"
        case .quickScan(.undefended): "Undefended pieces"
        case .target(.red): "Red targets"
        case .target(.orange): "Orange targets"
        case .target(.kingZone): "King-zone squares"
        case .target(.fork): "Fork squares"
        case .arrow(.check): "Checks"
        case .arrow(.capture): "Captures"
        case .arrow(.threat): "Threats"
        }
    }

    /// The step it belongs to: "Quick scan", "Targets" or "Arrows".
    var step: String {
        switch self {
        case .quickScan: "Quick scan"
        case .target: "Targets"
        case .arrow: "Arrows"
        }
    }
}
