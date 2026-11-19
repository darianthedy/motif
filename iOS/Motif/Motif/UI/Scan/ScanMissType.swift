import Foundation

/// What a missed square or arrow was, as the feedback card's icon shows it: the shape says the
/// step, the colour the side, the glyph the kind (Legend). Targets aren't graded (v6), so none. Unlike
/// `ScanMissCategory` an arrow keeps its side, since yours and theirs look different.
enum ScanMissType: Hashable, Sendable {
    /// A quick-scan square; nil when the square is missed but not in the answer's list.
    case quickScan(ScanSquare.Kind?)
    case arrow(ScanArrow.Kind, ScanArrow.Side)

    /// "Attacked", "Their threat": the legend's name and what VoiceOver reads.
    var label: String {
        switch self {
        case .quickScan(let kind?): kind == .opened ? "Opened line" : kind.label
        case .quickScan(nil): "Changed"
        case let .arrow(kind, side): (side == .own ? "Your " : "Their ") + kind.rawValue
        }
    }

    /// Every type the legend lists, by step.
    static let quickScanTypes: [ScanMissType] = ScanSquare.Kind.allCases.map { .quickScan($0) }
    /// Yours and theirs side by side, kind by kind, so the two columns read as the two sides.
    static let arrowTypes: [ScanMissType] = ScanArrow.Kind.allCases.flatMap { [.arrow($0, .own), .arrow($0, .theirs)] }
}

/// One line of the feedback card: a type's icon once, then every miss of that type.
struct ScanMissGroup: Equatable, Sendable {
    var type: ScanMissType
    /// Squares ("f6", "Qd2") or moves in SAN ("Nb5", "Bxf7+"), in the order they were missed.
    var items: [String]

    /// "Their threat: Nb5, Bh8", for VoiceOver.
    var spoken: String { "\(type.label): \(items.joined(separator: ", "))" }

    /// The pairs grouped by type in order of first appearance.
    static func grouped(_ pairs: [(ScanMissType, String)]) -> [ScanMissGroup] {
        var groups: [ScanMissGroup] = []
        for (type, item) in pairs {
            if let index = groups.firstIndex(where: { $0.type == type }) { groups[index].items.append(item) }
            else { groups.append(ScanMissGroup(type: type, items: [item])) }
        }
        return groups
    }
}
