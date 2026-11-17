import Foundation

/// One calendar week of graded scan attempts: a point on the Stats trend line.
struct ScanWeek: Equatable, Sendable, Identifiable {
    /// The week's first day, in the calendar the stats were worked out in.
    var start: Date
    var played: Int
    var solved: Int
    var flagRight: Int
    var quickScanMedianMs: Double?

    var id: Date { start }
    var solvedRate: Double { played == 0 ? 0 : Double(solved) / Double(played) }
    var flagAccuracy: Double { played == 0 ? 0 : Double(flagRight) / Double(played) }
}
