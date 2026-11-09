import SwiftUI

/// The board screens' layout rule (plan §7 "Board layout rule"): `boardGeom` in
/// `design/iphone-duo/kit.js`, without its device table. A pure function from the
/// container (inside the safe area and the bars) to a mode, a board size and the
/// column's frame, so every pose takes the same path and `AnyLayout` can switch
/// between the modes without losing state.
/// - Compact width (O, Split View, iPhone): stacked, the board at the full width
///   minus the margins (O 328 pt with the eval bar, 350 pt without; decision 5).
/// - Regular, wider than tall (IL, pinned video, iPad landscape): two panes, the
///   board capped by the height and by a column of at least `minColumnWidth`
///   (504 pt on IL, decision 11).
/// - Regular, taller than wide (IP, iPad portrait): stacked, the board by the width
///   but leaving the column `minColumnHeight` (512 pt on IP).
/// - An active fold division (plan §6.4, §6.16; D07) puts the split on the fold, so
///   no square crosses it: running top to bottom (FB) → `pages`, the board on the
///   leading page (Analysis 392 pt with the eval bar, sessions 416 pt) and the column
///   on the trailing one; running across (FT) → `halves`, the board above it (272 pt,
///   decision 10) and the column below. A thin strip at an edge (the Split View inner
///   edge, 13.5 pt, F33; pinned video bent) is an inset on that edge, not a split.
/// Regular boards snap down to a multiple of 8 pt, so squares are whole points.
struct BoardLayout: Equatable {
    enum Mode: Equatable { case stack, panes, pages, halves }
    let mode: Mode
    let compact: Bool
    /// The board's side.
    let board: CGFloat
    /// Side margin of the screen: 16 pt compact, 20 pt regular (§6.7).
    let margin: CGFloat
    /// Between the eval bar and the board.
    let evalGap: CGFloat
    /// In the container's coordinates. Nil when the bar is hidden.
    let evalFrame: CGRect?
    let boardFrame: CGRect
    /// The moves, lines, comment and pickers: under the board, or beside it.
    let column: CGRect
    /// The board's side of the division (`pages`, `halves`), else the board with its eval bar.
    /// Session complete puts its heading here.
    let boardSide: CGRect
    /// The padding around the `AnyLayout` stack, so the board pane and the column land on
    /// their frames: the margins, the 8 pt insets and any strip at an edge.
    let padding: EdgeInsets
    /// The stack's spacing between the board pane and the column; on a fold it spans the division.
    let spacing: CGFloat

    /// Board and column side by side (`HStackLayout`), else one above the other.
    var sideBySide: Bool { mode == .panes || mode == .pages }
    /// A short column (O, SV, IP): engine lines replace the move list, the
    /// alternatives are one scrolling row and the comment shows one line (F7, F8).
    var short: Bool { column.height < Self.shortColumn }

    static let evalBarWidth: CGFloat = 14
    /// Between the board and the column beside it.
    static let paneGap: CGFloat = 24
    /// Between the board and the column under it.
    static let stackGap: CGFloat = 12
    /// Above the board and under the column.
    static let inset: CGFloat = 8
    static let shortColumn: CGFloat = 300
    /// What a stacked regular column keeps: engine lines, a comment and alternatives fit.
    static let minColumnHeight: CGFloat = 240
    /// What the column beside the board keeps: 263 pt of content (decision 11) and
    /// its 16 pt inset.
    static let minColumnWidth: CGFloat = 279
    /// A compact column never drops below about four move rows, whatever the height.
    static let compactMinColumnHeight: CGFloat = 160
    /// A division with less than this on one side is a strip at that edge (Split View's
    /// inner edge, pinned video bent), not a fold through the content.
    static let minFoldSide: CGFloat = 100
    /// On a page, between the board and the division (the canvas's FB page).
    static let pageGap: CGFloat = 16
    /// On the trailing page: after the division, and at the trailing edge.
    static let pageLead: CGFloat = 4, pageTrail: CGFloat = 16

    /// - Parameters:
    ///   - container: the screen's content size, inside the safe area and the bars.
    ///   - compact: the horizontal size class is compact.
    ///   - evalBar: the evaluation bar sits beside the board.
    ///   - division: the fold's active reserved region in the container's coordinates
    ///     (`motifDivision`), margins included; nil when flat or before iOS 27.1.
    init(container: CGSize, compact: Bool, evalBar: Bool,
         minColumnHeight: CGFloat = BoardLayout.minColumnHeight, minColumnWidth: CGFloat = BoardLayout.minColumnWidth,
         division: CGRect? = nil) {
        let full = CGRect(x: 0, y: 0, width: max(0, container.width), height: max(0, container.height))
        // The area the board screen uses: the container less any strip at an edge, and the fold if one splits it.
        var area = full
        var fold: CGRect?
        if let raw = division, !full.isEmpty {
            let d = raw.intersection(full)
            if !d.isNull, d.width > 0, d.height > 0 {
                if d.height >= d.width {
                    let before = d.minX - full.minX, after = full.maxX - d.maxX
                    if min(before, after) >= Self.minFoldSide { fold = d }
                    else if before <= after { area = CGRect(x: d.maxX, y: 0, width: after, height: full.height) }
                    else { area = CGRect(x: 0, y: 0, width: before, height: full.height) }
                } else {
                    let before = d.minY - full.minY, after = full.maxY - d.maxY
                    if min(before, after) >= Self.minFoldSide { fold = d }
                    else if before <= after { area = CGRect(x: 0, y: d.maxY, width: full.width, height: after) }
                    else { area = CGRect(x: 0, y: 0, width: full.width, height: before) }
                }
            }
        }
        let ox = area.minX, oy = area.minY
        let w = area.width, h = area.height
        let margin: CGFloat = compact ? 16 : 20
        let evalGap: CGFloat = compact ? 4 : 6
        let slot = evalBar ? Self.evalBarWidth + evalGap : 0
        let snap = { (value: CGFloat) in max(0, (value / 8).rounded(.down) * 8) }
        self.compact = compact; self.margin = margin; self.evalGap = evalGap
        let board: CGFloat, boardX: CGFloat
        let mode: Mode
        if let d = fold, d.height >= d.width {
            // Book (FB): the board on the leading page, by the page's width and the height.
            board = min(snap(d.minX - margin - slot - Self.pageGap), snap(h - 2 * Self.inset))
            mode = .pages
            boardX = margin + slot
        } else if let d = fold {
            // Tabletop (FT): the board above the division, centred as on IP.
            board = min(snap(w - 2 * margin - slot), snap(d.minY - 2 * Self.inset))
            mode = .halves
            boardX = (w - slot - board) / 2 + slot
        } else if compact {
            // Beside the bar the trailing margin is 20 pt, as on the canvas: 382 − 16 − 18 − 20 = 328.
            let byWidth = (w - margin - slot - (evalBar ? 20 : margin)).rounded(.down)
            let byHeight = (h - Self.inset - Self.stackGap - Self.compactMinColumnHeight).rounded(.down)
            board = max(0, min(byWidth, byHeight))
            mode = .stack
            boardX = margin + slot + max(0, byWidth - board) / 2
        } else if w > h {
            // The board keeps its size with the bar hidden; the column takes the room.
            let reserved = Self.evalBarWidth + evalGap
            board = min(snap(w - 2 * margin - reserved - Self.paneGap - minColumnWidth), snap(h - 2 * Self.inset))
            mode = .panes
            boardX = margin + slot
        } else {
            board = min(snap(w - 2 * margin - slot), snap(h - 2 * Self.inset - Self.stackGap - minColumnHeight))
            mode = .stack
            boardX = (w - slot - board) / 2 + slot
        }
        self.mode = mode
        self.board = board
        boardFrame = CGRect(x: ox + boardX, y: oy + Self.inset, width: board, height: board)
        evalFrame = evalBar ? CGRect(x: ox + boardX - slot, y: oy + Self.inset, width: Self.evalBarWidth, height: board) : nil
        let pane = CGRect(x: ox + boardX - slot, y: oy + Self.inset, width: board + slot, height: board)
        // Edges of the container outside the area (a strip), added to the padding.
        let lead = area.minX - full.minX, trail = full.maxX - area.maxX
        let top = area.minY - full.minY, bottom = full.maxY - area.maxY
        switch mode {
        case .stack:
            let y = oy + Self.inset + board + Self.stackGap
            column = CGRect(x: ox + margin, y: y, width: max(0, w - 2 * margin), height: max(0, area.maxY - Self.inset - y))
            boardSide = pane
            spacing = Self.stackGap
            padding = EdgeInsets(top: top + Self.inset, leading: lead + margin, bottom: bottom + Self.inset, trailing: trail + margin)
        case .panes:
            let x = pane.maxX + Self.paneGap
            column = CGRect(x: x, y: oy + Self.inset, width: max(0, area.maxX - margin - x), height: max(0, h - 2 * Self.inset))
            boardSide = pane
            spacing = Self.paneGap
            padding = EdgeInsets(top: top + Self.inset, leading: lead + margin, bottom: bottom + Self.inset, trailing: trail + margin)
        case .pages:
            let d = fold ?? .zero
            let x = d.maxX + Self.pageLead
            column = CGRect(x: x, y: Self.inset, width: max(0, full.maxX - Self.pageTrail - x), height: max(0, h - 2 * Self.inset))
            boardSide = CGRect(x: margin, y: Self.inset, width: max(0, d.minX - margin - Self.pageGap), height: max(0, h - 2 * Self.inset))
            spacing = x - pane.maxX
            padding = EdgeInsets(top: Self.inset, leading: margin, bottom: Self.inset, trailing: Self.pageTrail)
        case .halves:
            let d = fold ?? .zero
            let y = d.maxY + Self.inset
            column = CGRect(x: margin, y: y, width: max(0, w - 2 * margin), height: max(0, full.maxY - Self.inset - y))
            boardSide = CGRect(x: margin, y: Self.inset, width: max(0, w - 2 * margin), height: max(0, d.minY - 2 * Self.inset))
            spacing = y - pane.maxY
            padding = EdgeInsets(top: Self.inset, leading: margin, bottom: Self.inset, trailing: margin)
        }
    }
}
