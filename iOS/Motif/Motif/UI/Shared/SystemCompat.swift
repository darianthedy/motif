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
extension View {
    /// A screen's custom actions, the ⋯ menu (F16). On iOS 27.1 they go in the system
    /// toolbar overflow menu (`toolbarOverflowMenu`, the modifier form of
    /// `ToolbarOverflowMenu`), which the vertical side bar keeps reachable; the menu's
    /// items keep their titles there, so UI tests find them by title. Before 27.1 it is
    /// today's ellipsis `Menu` at the trailing edge of the navigation bar, with
    /// `title` as its label and `identifier` for the UI tests.
    /// `shown: false` takes the menu away (edit mode) without changing the view's identity.
    @ViewBuilder func motifOverflowMenu<Items: View>(_ title: String, identifier: String, shown: Bool = true,
                                                     @ViewBuilder items: () -> Items) -> some View {
        let content = items()
        if #available(iOS 27.1, *) {
            toolbarOverflowMenu { if shown { content } }
        } else {
            toolbar {
                if shown {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu(title, systemImage: "ellipsis") { content }.accessibilityIdentifier(identifier)
                    }
                }
            }
        }
    }
}
