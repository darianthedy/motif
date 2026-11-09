import CoreGraphics

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
/// Regular boards snap down to a multiple of 8 pt, so squares are whole points.
struct BoardLayout: Equatable {
    enum Mode: Equatable { case stack, panes }
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

    /// - Parameters:
    ///   - container: the screen's content size, inside the safe area and the bars.
    ///   - compact: the horizontal size class is compact.
    ///   - evalBar: the evaluation bar sits beside the board.
    ///   - division: the fold's reserved region, when active. Accepted and ignored
    ///     until D07 puts the split on it.
    init(container: CGSize, compact: Bool, evalBar: Bool,
         minColumnHeight: CGFloat = BoardLayout.minColumnHeight, minColumnWidth: CGFloat = BoardLayout.minColumnWidth,
         division: CGRect? = nil) {
        let w = max(0, container.width), h = max(0, container.height)
        let margin: CGFloat = compact ? 16 : 20
        let evalGap: CGFloat = compact ? 4 : 6
        let slot = evalBar ? Self.evalBarWidth + evalGap : 0
        let snap = { (value: CGFloat) in max(0, (value / 8).rounded(.down) * 8) }
        self.compact = compact; self.margin = margin; self.evalGap = evalGap
        let board: CGFloat, boardX: CGFloat
        if compact {
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
        self.board = board
        boardFrame = CGRect(x: boardX, y: Self.inset, width: board, height: board)
        evalFrame = evalBar ? CGRect(x: boardX - slot, y: Self.inset, width: Self.evalBarWidth, height: board) : nil
        switch mode {
        case .stack:
            let y = Self.inset + board + Self.stackGap
            column = CGRect(x: margin, y: y, width: max(0, w - 2 * margin), height: max(0, h - Self.inset - y))
        case .panes:
            let x = boardFrame.maxX + Self.paneGap
            column = CGRect(x: x, y: Self.inset, width: max(0, w - margin - x), height: max(0, h - 2 * Self.inset))
        }
    }
}
