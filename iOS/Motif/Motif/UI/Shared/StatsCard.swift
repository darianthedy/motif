import SwiftUI

/// Shared by a puzzle collection and the Scan tab's pool.
/// Solved / To review / New counts over one stacked bar.
struct StatsCard: View {
    let stats: Stats
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RowStack {
                figure(stats.solved, "Solved", Color.motifAccentStrong)
                figure(stats.failed, "To Review", .orange)
                figure(stats.unseen, "New", .motifSecondaryText)
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    segment(stats.solved, Color.motifAccent, geometry.size.width)
                    segment(stats.failed, .orange, geometry.size.width)
                    segment(stats.unseen, Color.secondary.opacity(0.3), geometry.size.width)
                }
            }
            .frame(height: 8).clipShape(.capsule)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
    private func figure(_ count: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)").font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.footnote).foregroundStyle(.motifSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func segment(_ count: Int, _ color: Color, _ width: CGFloat) -> some View {
        if count > 0, stats.total > 0 {
            let gaps = CGFloat([stats.solved, stats.failed, stats.unseen].filter { $0 > 0 }.count - 1) * 2
            color.frame(width: max(0, (width - gaps) * CGFloat(count) / CGFloat(stats.total)))
        }
    }
}
