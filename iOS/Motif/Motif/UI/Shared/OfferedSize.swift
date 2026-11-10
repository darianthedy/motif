import SwiftUI

extension View {
    /// Lays this view out in the space its parent offers and reads that space into `size`, for
    /// `BoardLayout`. The size comes from a `Color.clear` that takes exactly the offer, not from
    /// this view: the board screens size their content from the reading, so measuring the content
    /// fed back. A column whose content was wider than its share (the five-piece row beside the
    /// board) or a board taller than the space grew the reading, which grew the board, without end
    /// (the missing-piece session hung on IL and the iPad; the iPad session board ran off at 840 pt).
    func motifOfferedSize(_ size: Binding<CGSize>) -> some View {
        Color.clear
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size.wrappedValue = $0 }
            .overlay(alignment: .top) { self }
    }
}
