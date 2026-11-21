import Foundation

/// What the Stats trend line plots, one week per point.
enum ScanTrendMetric: String, CaseIterable, Identifiable, Sendable {
    case quickScan, flagAccuracy, solved

    var id: Self { self }

    var title: String {
        switch self {
        case .quickScan: "Quick Scan"
        case .flagAccuracy: "Calls"
        case .solved: "Solved"
        }
    }

    /// The value axis' name, for the chart and VoiceOver.
    var axisTitle: String {
        switch self {
        case .quickScan: "Median quick scan, seconds"
        case .flagAccuracy: "Tactic/Quiet calls right, percent"
        case .solved: "Puzzles solved, percent"
        }
    }

    /// The week's value: seconds, or a percent from 0 to 100. Nil when the week has none.
    func value(_ week: ScanWeek) -> Double? {
        switch self {
        case .quickScan: week.quickScanMedianMs.map { $0 / 1000 }
        case .flagAccuracy: week.flagAccuracy * 100
        case .solved: week.solvedRate * 100
        }
    }

    /// The quick scan's target (10 s) as a rule on the chart; the others have none.
    var target: Double? { self == .quickScan ? Double(ScanTiming.targetMs(.quickScan)) / 1000 : nil }

    /// An axis tick: whole seconds ("10 s") or a percent.
    func axisLabel(_ value: Double) -> String {
        self == .quickScan ? value.formatted(.number.precision(.fractionLength(0))) + " s" : label(value)
    }

    /// "7.4 s" or "82 %", as VoiceOver and the selection read it.
    func label(_ value: Double) -> String {
        self == .quickScan
            ? value.formatted(.number.precision(.fractionLength(1))) + " s"
            : (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
