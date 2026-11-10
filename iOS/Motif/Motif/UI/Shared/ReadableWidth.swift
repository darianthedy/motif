import SwiftUI

/// The readable content width on regular width (Duo plan §6.7): text, cards and empty
/// states stop at ~672 pt and centre in a wider column. Lists are left to the system.
let readableContentWidth: CGFloat = 672

extension View {
    /// Caps this view at the readable width and centres it in whatever is left over, so an
    /// iPad-sized detail column doesn't stretch it; narrower columns are unaffected.
    func readableWidth() -> some View {
        frame(maxWidth: readableContentWidth).frame(maxWidth: .infinity)
    }
}
