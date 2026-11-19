import SwiftUI

/// What each miss icon on the feedback card means, from the ⓘ in the toolbar. The step on screen
/// comes first; the icons are in two columns so the whole legend fits without scrolling on a phone.
struct ScanLegendSheet: View {
    let step: ScanStep
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title + (section.current ? " · This Step" : ""))
                                .font(.footnote.weight(.semibold)).textCase(.uppercase)
                                .foregroundStyle(section.current ? Color.orange : .motifSecondary)
                                .accessibilityAddTraits(.isHeader)
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                                ForEach(section.types, id: \.self) { type in
                                    HStack(spacing: 10) {
                                        ScanMissIcon(type: type)
                                        Text(type.label).font(.body)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Legend").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }.accessibilityIdentifier("scan-legend-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("scan-legend-sheet")
    }

    /// One column at accessibility text sizes, where two would truncate the names.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    private struct Section { let title: String; let types: [ScanMissType]; let current: Bool }

    private var sections: [Section] {
        let all = [
            Section(title: "Quick Scan", types: ScanMissType.quickScanTypes, current: step == .quickScan || step == .lastMove),
            Section(title: "Arrows", types: ScanMissType.arrowTypes, current: step == .arrows),
        ]
        return all.filter(\.current) + all.filter { !$0.current }
    }
}
