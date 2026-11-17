import Foundation

/// The Markdown summary Caïssa gets through the share sheet (Scan plan §8): the Stats numbers
/// and the most recent fails. Numbers and dates use a fixed format, so the text reads the same
/// on any device and in any language.
enum ScanStatsExport {
    static func markdown(_ stats: ScanStats, now: Date, calendar: Calendar = .current) -> String {
        var lines = ["# Motif Scan Training summary", "",
                     "Exported \(day(now, calendar)). \(stats.played) puzzles played, \(stats.solved) solved.", ""]
        let target = ScanTiming.targetMs(.quickScan) / 1000
        lines.append("- Median quick scan: " + (stats.quickScanMedianMs.map { seconds($0) + " (target \(target) s)" } ?? "none yet"))
        lines.append("- Flag accuracy: " + (stats.flagAccuracy.map { "\(percent($0)) (\(stats.flagRight) of \(stats.played) calls right)" } ?? "none yet"))
        lines.append("- Most missed: " + (stats.mostMissed.map { "\($0.category.title.lowercased()), \($0.missed) of \($0.expected) missed" } ?? "nothing yet"))
        lines.append("- Flag puzzles in the pool: " + (stats.flagShare.map { "\(percent($0)) (\(stats.flagPuzzles) of \(stats.poolSize))" } ?? "no puzzles"))
        if !stats.misses.isEmpty {
            lines += ["", "## Misses by category", ""]
            lines += stats.misses.map { "- \($0.category.step), \($0.category.title.lowercased()): \($0.missed) of \($0.expected) missed" }
        }
        if !stats.weeks.isEmpty {
            lines += ["", "## Weekly", "", "| Week of | Played | Solved | Median quick scan | Flag accuracy |", "|---|---|---|---|---|"]
            lines += stats.weeks.map { week in
                "| \(day(week.start, calendar)) | \(week.played) | \(percent(week.solvedRate)) | \(week.quickScanMedianMs.map(seconds) ?? "–") | \(percent(week.flagAccuracy)) |"
            }
        }
        if !stats.recentFails.isEmpty {
            lines += ["", "## Recent fails", ""]
            for (index, fail) in stats.recentFails.enumerated() {
                let missed = fail.missed.isEmpty ? "" : "; missed " + fail.missed.joined(separator: "; ")
                lines.append("\(index + 1). `\(fail.fenBefore)`, last move \(fail.lastMove): \(fail.reason)\(missed).")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
    static func seconds(_ ms: Double) -> String { String(format: "%.1f s", locale: posix, ms / 1000) }
    static func percent(_ share: Double) -> String { String(format: "%.0f %%", locale: posix, share * 100) }
    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
