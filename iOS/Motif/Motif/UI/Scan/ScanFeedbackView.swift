import SwiftUI

/// A graded step's feedback, inline under or beside the board, never an alert: the verdict as a
/// symbol and title, a short reason when there is one, and the step's time.
struct ScanFeedbackView: View {
    let feedback: ScanFeedback
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(feedback.title, systemImage: feedback.verdict.systemImage)
                .font(.headline).foregroundStyle(tint)
                .accessibilityIdentifier("scan-feedback-title")
            if !feedback.reason.isEmpty {
                Text(feedback.reason).font(.body).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scan-feedback-reason")
            }
            ForEach(feedback.misses, id: \.type) { group in
                // One line per type: the icon once, then its misses; a long list wraps under itself.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ScanMissIcon(type: group.type).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    Text(group.items.joined(separator: ", ")).font(.body.weight(.medium)).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(group.spoken)
                .accessibilityIdentifier("scan-feedback-miss")
            }
            if let note = feedback.note {
                Text(note).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            if let time = feedback.time {
                Text(time).font(.subheadline).monospacedDigit().foregroundStyle(.motifSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scan-feedback")
    }
    private var tint: Color {
        switch feedback.verdict {
        case .pass: .motifAccentStrong
        case .softMiss: .orange
        case .fail: .red
        }
    }
}
