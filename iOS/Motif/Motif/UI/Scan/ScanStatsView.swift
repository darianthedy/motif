import SwiftUI

/// Scan plan §8: how the scans are going, from the attempts on this device's copy of the
/// library: median quick scan, flag accuracy, what gets missed, a weekly trend and the share of
/// Tactic puzzles. **Export for Caïssa** shares the same numbers and the recent fails as Markdown.
struct ScanStatsView: View {
    @Environment(AppState.self) private var app
    @State private var metric: ScanTrendMetric = .quickScan

    var body: some View {
        let stats = app.store.library.map { ScanStats($0) } ?? ScanStats()
        Group {
            if stats.played == 0 {
                EmptyState(title: "No Results Yet", systemImage: "chart.line.uptrend.xyaxis",
                           description: "Play a scan session and your times, calls and misses show here.")
                    .readableWidth()
            } else {
                content(stats)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Stats")
        .toolbar {
            if stats.played > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: ScanStatsExport.markdown(stats, now: .now), subject: Text("Motif Scan Training summary"),
                              preview: SharePreview("Motif Scan Training summary")) {
                        Label("Export for Caïssa", systemImage: "square.and.arrow.up")
                    }.accessibilityIdentifier("scan-stats-export")
                }
            }
        }
    }

    private func content(_ stats: ScanStats) -> some View {
        List {
            Section {
                LabeledContent {
                    Text(stats.quickScanMedianMs.map(seconds) ?? "–").monospacedDigit()
                } label: {
                    Text("Median Quick Scan")
                    Text("Target \(ScanTiming.targetMs(.quickScan) / 1000) s")
                }.accessibilityIdentifier("scan-stats-median")
                LabeledContent {
                    Text(stats.flagAccuracy.map(percent) ?? "–").monospacedDigit()
                } label: {
                    Text("Call Accuracy")
                    Text("\(stats.flagRight) of \(countLabel(stats.played, "call")) right")
                }.accessibilityIdentifier("scan-stats-accuracy")
                LabeledContent {
                    Text(stats.mostMissed?.category.title ?? "Nothing")
                } label: {
                    Text("Most Missed")
                    if let most = stats.mostMissed { Text("\(most.missed) of \(most.expected) missed") }
                }.accessibilityIdentifier("scan-stats-most-missed")
            } footer: {
                Text("From \(countLabel(stats.played, "puzzle")) played, \(stats.solved) solved. Skips aren’t counted.")
            }
            Section("By Week") {
                Picker("Metric", selection: $metric) {
                    ForEach(ScanTrendMetric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).accessibilityIdentifier("scan-stats-metric")
                ScanTrendChart(weeks: stats.weeks, metric: metric).padding(.vertical, 8)
            }
            Section("Missed") {
                ForEach(stats.misses, id: \.category) { tally in
                    LabeledContent {
                        Text("\(tally.missed) of \(tally.expected)").monospacedDigit()
                    } label: {
                        Text(tally.category.title)
                        Text(tally.category.step)
                    }
                }
            }
            Section {
                LabeledContent {
                    Text(stats.flagShare.map(percent) ?? "–").monospacedDigit()
                } label: {
                    Text("Tactic Puzzles")
                    Text("\(stats.flagPuzzles) of \(countLabel(stats.poolSize, "puzzle")) in the pool")
                }.accessibilityIdentifier("scan-stats-flag-share")
            } footer: {
                Text("A share near 100 % means nearly every position is a Tactic, and the call teaches little.")
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("scan-stats-list")
    }

    private func seconds(_ ms: Double) -> String { (ms / 1000).formatted(.number.precision(.fractionLength(1))) + " s" }
    private func percent(_ share: Double) -> String { share.formatted(.percent.precision(.fractionLength(0))) }
}
