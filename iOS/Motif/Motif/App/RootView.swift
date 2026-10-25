import SwiftUI

/// Project-shell placeholder. The account and library screens arrive in P06.
struct RootView: View {
    var body: some View {
        Text("Motif")
            .font(.largeTitle.weight(.semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
    }
}

#Preview {
    RootView()
}
