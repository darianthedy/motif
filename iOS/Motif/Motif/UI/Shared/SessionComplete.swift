import SwiftUI

/// The end of a session, puzzles or scan: what was solved and missed, and Done.
struct SessionComplete: View {
    static let maxWidth: CGFloat = 480
    @Environment(\.horizontalSizeClass) private var sizeClass
    let progress: RunProgress
    /// The first tile's label: "Solved cleanly" for puzzles, "Passed" for scans.
    var solvedLabel = "Solved cleanly"
    let done: () -> Void
    @State private var container: CGSize = .zero
    @State private var division: CGRect?
    var body: some View {
        // Content at most 480 pt wide, centred (F27). On a fold the heading takes the board's
        // side (the leading page, the top half) and the tiles and Done the other, so nothing
        // sits on the division (D07). One view tree: `AnyLayout` switches.
        let layout = BoardLayout(container: container, compact: sizeClass == .compact, evalBar: false, division: division)
        let folded = layout.mode == .pages || layout.mode == .halves
        // Across the division: from the board's side to the column's.
        let gap = layout.mode == .pages ? layout.column.minX - layout.boardSide.maxX : layout.column.minY - layout.boardSide.maxY
        let stack = layout.mode == .pages
            ? AnyLayout(HStackLayout(alignment: .center, spacing: gap))
            : AnyLayout(VStackLayout(alignment: .center, spacing: folded ? gap : 24))
        stack {
            VStack(spacing: 16) {
                if !folded { Spacer() }
                Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(Color.motifAccent).accessibilityHidden(true)
                Text("Session Complete").font(.title.bold())
            }
            .frame(width: layout.mode == .pages ? layout.boardSide.width : nil, height: layout.mode == .halves ? layout.boardSide.height : nil)
            .frame(maxHeight: layout.mode == .pages ? .infinity : nil)
            VStack(spacing: 24) {
                // Stacked at accessibility sizes, where two tiles leave no room for their labels.
                RowStack(spacing: 12) {
                    tile(progress.solved, solvedLabel, .motifAccentStrong)
                    tile(progress.failed, "Missed", .orange)
                }.padding(.horizontal)
                Spacer()
                Button(action: done) { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent).controlSize(.large).padding()
                    .accessibilityIdentifier("session-done")
            }
            .frame(maxWidth: SessionComplete.maxWidth).frame(maxWidth: .infinity, maxHeight: folded ? .infinity : nil)
        }
        .padding(folded ? layout.padding : EdgeInsets())
        .frame(maxWidth: folded ? .infinity : SessionComplete.maxWidth).frame(maxWidth: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { container = $0 }
        .motifDivision($division)
    }
    private func tile(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.largeTitle.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.subheadline).foregroundStyle(.motifSecondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }
}
