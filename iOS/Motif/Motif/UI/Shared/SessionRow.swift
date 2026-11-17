import SwiftUI

/// "Session in Progress" with Resume, and Discard Session under it: a puzzle collection's
/// open run, and the Scan tab's. Discarding writes straight to the database, so it needs a connection.
struct SessionRow: View {
    var title = "Session in Progress"
    let remaining: Int
    let online: Bool
    var identifier = "session"
    let resume: () -> Void
    let discard: () -> Void
    var body: some View {
        Section {
            RowStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text("\(remaining) left").font(.subheadline).foregroundStyle(.motifSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button("Resume", systemImage: "play.fill", action: resume)
                    .labelStyle(.titleAndIcon).foregroundStyle(.white)
                    .buttonStyle(.glassProminent).buttonBorderShape(.capsule).fixedSize()
                    .accessibilityIdentifier("resume-" + identifier)
            }
            .padding(.vertical, 4)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            Button("Discard Session", role: .destructive, action: discard)
                .disabled(!online).accessibilityIdentifier("discard-" + identifier)
        }
    }
}
