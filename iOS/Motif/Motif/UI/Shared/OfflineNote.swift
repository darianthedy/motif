import SwiftUI

/// The first row of an edit sheet while offline, where it explains the disabled confirm
/// before anything else (F19). Both import sheets use it.
struct OfflineNote: View {
    let text: String
    let identifier: String
    var body: some View {
        Section {
            Label(text, systemImage: "wifi.slash")
                .foregroundStyle(.motifSecondary).accessibilityIdentifier(identifier)
        }
    }
}
