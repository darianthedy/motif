import SwiftUI

/// The one home for iOS 27.1 APIs (`ToolbarOverflowMenu`, `toolbarVerticalBehavior`,
/// `toolbarVerticalEdge`, `ReservedRegion` / `reservedRegions`, `ArrangementView`).
/// The deployment target stays 26.1, so each wrapper checks `#available(iOS 27.1, *)`
/// and falls back to today's behaviour; views call the wrapper, never the API.
/// See "Motif - iOS iPhone Duo Plan.md" §9.2 rule 4.
extension View {
    /// Opts this view out of the vertical side bar, so its toolbar items stay in the
    /// horizontal top and bottom bars. iOS 26 has no vertical bar, so it's a no-op there.
    @ViewBuilder func motifToolbarVerticalBehaviorDisabled() -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
    }
}
