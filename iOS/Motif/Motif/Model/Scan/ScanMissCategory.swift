import Foundation

/// What a scan can miss, by the maker's own labels (Scan plan §8): a quick-scan square's kind or
/// an arrow's kind. Targets aren't graded (v6), so they are no category.
enum ScanMissCategory: Hashable, Sendable, CaseIterable {
    case quickScan(ScanSquare.Kind)
    case arrow(ScanArrow.Kind)

    static var allCases: [ScanMissCategory] {
        ScanSquare.Kind.allCases.map(Self.quickScan) + ScanArrow.Kind.allCases.map(Self.arrow)
    }

    /// "Undefended squares", "Red targets", "Their captures" style names, for the screen and the export.
    var title: String {
        switch self {
        case .quickScan(.attacked): "Attacked squares"
        case .quickScan(.opened): "Opened lines"
        case .quickScan(.undefended): "Undefended pieces"
        case .quickScan(.unpinned): "Unpinned pieces"
        case .quickScan(.hanging): "Hanging pieces"
        case .arrow(.check): "Checks"
        case .arrow(.capture): "Captures"
        case .arrow(.threat): "Threats"
        }
    }

    /// The step it belongs to: "Quick scan" or "Arrows".
    var step: String {
        switch self {
        case .quickScan: "Quick scan"
        case .arrow: "Arrows"
        }
    }
}
