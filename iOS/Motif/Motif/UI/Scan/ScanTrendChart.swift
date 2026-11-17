import Charts
import SwiftUI

/// One metric by week: a single line, so the picker names it and there's no legend. The quick
/// scan's target is a dashed rule. Touching the chart shows that week's value.
struct ScanTrendChart: View {
    let weeks: [ScanWeek]
    let metric: ScanTrendMetric
    @State private var selected: Date?

    var body: some View {
        let points = weeks.compactMap { week in metric.value(week).map { (week, $0) } }
        Chart {
            if let target = metric.target {
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(.motifSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Target").font(.footnote).foregroundStyle(.motifSecondary)
                    }
            }
            ForEach(points, id: \.0.id) { week, value in
                LineMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value(metric.axisTitle, value))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value(metric.axisTitle, value))
                    .symbolSize(48)
            }
            .foregroundStyle(Color.motifAccentStrong)
            if let selected, let point = points.first(where: { Calendar.current.isDate($0.0.start, equalTo: selected, toGranularity: .weekOfYear) }) {
                RuleMark(x: .value("Week", point.0.start, unit: .weekOfYear))
                    .foregroundStyle(.motifSecondary.opacity(0.5))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.0.start, format: .dateTime.month(.abbreviated).day()).foregroundStyle(.motifSecondary)
                            Text(metric.label(point.1)).font(.headline.monospacedDigit())
                            Text(countLabel(point.0.played, "puzzle")).foregroundStyle(.motifSecondary)
                        }
                        .font(.footnote)
                        .padding(8)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    }
            }
        }
        .chartYScale(domain: 0...yMax(points.map(\.1)))
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) { value in
            AxisGridLine().foregroundStyle(.secondary.opacity(0.3))
            AxisValueLabel { if let number = value.as(Double.self) { Text(metric.axisLabel(number)) } }
        } }
        .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) { _ in
            AxisValueLabel(format: .dateTime.month(.abbreviated).day(), collisionResolution: .greedy)
        } }
        .chartXSelection(value: $selected)
        .frame(minHeight: 180)
        .accessibilityChartDescriptor(ScanTrendDescriptor(weeks: weeks, metric: metric))
        .accessibilityIdentifier("scan-stats-chart")
    }

    /// Percents run to 100; times to the slowest week or the target, with room for the target's label.
    private func yMax(_ values: [Double]) -> Double {
        guard metric == .quickScan else { return 100 }
        return max(values.max() ?? 0, metric.target ?? 0) * 1.15
    }
}
