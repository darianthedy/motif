import SwiftUI

/// The one home for iOS 27.1 APIs (`ToolbarOverflowMenu`, `toolbarVerticalBehavior`,
/// `toolbarVerticalEdge`, `ReservedRegion` / `reservedRegions`, `ArrangementView`).
/// The deployment target stays 26.1, so each wrapper checks `#available(iOS 27.1, *)`
/// and falls back to today's behaviour; views call the wrapper, never the API.
/// See "Motif - iOS iPhone Duo Plan.md" §9.2 rule 4.
extension View {
    /// Opts this view out of the vertical side bar, so its toolbar items stay in the
    /// horizontal top and bottom bars. iOS 26 has no vertical bar, so it's a no-op there.
    /// `disabled: false` leaves the choice to the system (`.automatic`) without changing the
    /// view's identity, so a size-class switch keeps the view's state.
    @ViewBuilder func motifToolbarVerticalBehaviorDisabled(_ disabled: Bool = true) -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(disabled ? .disabled : .automatic)
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
extension GeometryProxy {
    /// The fold's active division (`ReservedRegion`, kind `.division`) in this view's own
    /// coordinates, margins included, as `BoardLayout` takes it (D07, plan §6.16). Nil when
    /// the division is inactive (open flat, closed) or before iOS 27.1. The frame is mirrored
    /// for right-to-left layouts (the default), matching the `AnyLayout` stacks it feeds.
    var motifDivision: CGRect? {
        if #available(iOS 27.1, *) {
            // Active regions only by default; iPhone Duo has one fold.
            return reservedRegions(kind: .division).first(where: { $0.isActive })?.frame
        }
        return nil
    }
}
extension View {
    /// Reads the active fold division of this view into `division`, in this view's coordinates,
    /// so it lines up with a container size read on the same view. Not `onHingeChange`: that is
    /// for effects, not layout (§1).
    func motifDivision(_ division: Binding<CGRect?>) -> some View {
        onGeometryChange(for: CGRect?.self) { $0.motifDivision } action: { division.wrappedValue = $0 }
    }
}
