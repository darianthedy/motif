import SwiftUI
import Foundation

/// The trend chart for VoiceOver's audio graph and chart summary (Scan plan §8).
struct ScanTrendDescriptor: AXChartDescriptorRepresentable {
    let weeks: [ScanWeek]
    let metric: ScanTrendMetric

    func makeChartDescriptor() -> AXChartDescriptor {
        let points = weeks.compactMap { week in metric.value(week).map { (week, $0) } }
        let values = points.map(\.1)
        // From zero, as the chart draws it: percents up to 100, times up to the slowest week or the target.
        let high = metric == .quickScan ? max(values.max() ?? 0, metric.target ?? 0) : 100
        let x = AXCategoricalDataAxisDescriptor(title: "Week", categoryOrder: points.map { week($0.0) })
        let y = AXNumericDataAxisDescriptor(title: metric.axisTitle, range: 0...high, gridlinePositions: metric.target.map { [$0] } ?? []) { metric.label($0) }
        let series = AXDataSeriesDescriptor(name: metric.title, isContinuous: true,
                                            dataPoints: points.map { AXDataPoint(x: week($0.0), y: $0.1) })
        return AXChartDescriptor(title: "\(metric.title) by week", summary: summary(values), xAxis: x, yAxis: y,
                                 additionalAxes: [], series: [series])
    }

    private func week(_ week: ScanWeek) -> String { "Week of " + week.start.formatted(.dateTime.month(.abbreviated).day()) }

    private func summary(_ values: [Double]) -> String? {
        guard let first = values.first, let last = values.last, values.count > 1 else { return nil }
        return "From \(metric.label(first)) to \(metric.label(last)) over \(values.count) weeks."
    }
}
