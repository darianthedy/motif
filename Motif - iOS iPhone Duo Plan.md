# Motif — iOS iPhone Duo Plan

> Investigate every iOS screen on the iPhone Duo (Apple's foldable, shipped
> 2026-10-23 with iOS 27.1) and produce mockups on a canvas for every screen in
> every state, on every display configuration the Duo can put the app in. Every
> design uses standard iOS containers and controls and follows the Human
> Interface Guidelines (§6).
>
> This plan covered **investigation and mockups** (Phases 0–5). Phase 6 turned the
> approved mockups into build prompts: slices D01–D11 in §9, run by
> `scripts/run-ios-duo-prompts.sh`.
>
> Prior work this builds on: UI refresh (`Motif - iOS UI Refresh Plan.md`,
> mockups https://claude.ai/artifact/LWDMhxnGuDKZFqkdQ79QCb), Analysis view
> update (https://claude.ai/artifact/3k2Bpr381a9BzaSCfyGgHj), puzzle → analysis
> (https://claude.ai/artifact/RKcf2qk5mBRwyKdTj1MhRN).
>
> Checked against the code at `fd6675b` and Apple's guidance on 2026-11-02.
> Decisions recorded 2026-11-03 (§10); Phase 5 review approved 2026-11-06
> (decisions 13–22, §8.6). Outer-display Analysis options:
> https://claude.ai/artifact/1jThHMrrJzkPHC77F25JR2
>
> Phase 4 canvases (`design/iphone-duo/`, open the HTML in a browser):
> Analysis (S15, S10) `analysis.html`; Session and detail (S09, S08)
> `session.html`; Shell and homes (S01–S04, S11, S17) `shell.html`; Lists (S06,
> S07, S12) `lists.html`; Sheets (S05, S13, S14, S16) `sheets.html`.

---

## 1. What the iPhone Duo changes

Sources are in §12. Apple publishes pixel sizes, not points. Anything marked
**verify** gets measured in Phase 1 before any mockup is drawn to scale.

| | Outer display | Inner display |
|---|---|---|
| Size | 5.4″, 1398 × 2034 px, 460 ppi | 7.6″ folding, 1878 × 2670 px, 430 ppi |
| Points (@3x) | 466 × 678 pt (matches the App Store screenshot size) | 669 × 951 pt from Apple's UI kit and App Store Connect (2007 × 2853 px), which suggests a slight downscale to the panel. Pixels ÷ 3 would give 626 × 890 pt. **verify** |
| Shape | ~1.45 : 1, much squatter than an iPhone 17 (402 × 874 pt, 2.17 : 1) | ~1.42 : 1; opens like a book, so it is wide when held as opened and the fold runs vertically through the middle |
| Size classes | compact × regular portrait, compact × compact landscape | **regular × regular in both orientations** |
| Bars | **Vertical, on the trailing edge** | Vertical in landscape, **horizontal in portrait** |
| Camera | hole-punch; Dynamic Island in the side space | under-display camera; Dynamic Island |
| Orientation | honors the app's declared orientations | **ignores the app's declared orientations** |

What Apple's guidance says (developer group-lab summary and tech talk):

- **Design for two size classes, not for each pose.** Keep the same controls,
  functionality and hierarchy on both displays, and make small adjustments
  rather than dramatic rearrangements. A bespoke tabletop layout is allowed but
  optional, and nothing may depend on a pose.
- **Folding and unfolding is a size-class and trait change, not a new scene.**
  The process stays alive, and scroll position, text input and keyboard
  sessions survive. Any state the app holds in a view has to survive the
  layout swap.
- **Lay out by size class and container size**, never by idiom, orientation or
  `UIScreen.main`. Safe-area insets are asymmetric, so handle each edge on its
  own. There is no single pose value and no Duo idiom.
- **Bars go vertical in every pose except open portrait.** The side space is
  shared with the status bar and Dynamic Island. Top toolbar items go to the
  top of it, bottom toolbar items to the bottom, and tab bars stay bottom
  aligned. Items too wide for it (text buttons, segmented controls) stay in the
  navigation bar. Without enough room, items collapse into an overflow menu.
- **Toolbar items need a title and a symbol.** The symbol shows in the vertical
  bar, and the title shows in overflow. Text-only items stay horizontal.
- **Custom bars don't move by themselves.** Detect the side space with
  `toolbarVerticalEdge`, position with `ReservedRegion`, or opt a full-width
  non-scrolling layout out with `toolbarVerticalBehavior`. Keep controls with
  the content they act on.
- **The fold is a reserved region.** In a partly folded pose it is a division
  region (`reservedRegions(kind: .division)`) that discrete controls must
  avoid. System components nudge themselves away from it. Scrolling content may
  cross it. In book pose, interactive elements go to the sides. Partly folded
  in portrait, they go to the bottom half.
- **Sidebars.** On the inner display iOS keeps a tab bar unless the app opts in
  with `.sidebarAdaptable`, which Apple suggests for information-dense apps.
  `NavigationSplitView` collapses to a single stack when closed and tiles when
  open, so one container serves both displays.
- **Sheets** use side controls on the outer display (a single-button sheet can
  opt out with `toolbarVerticalBehavior`) and sit centered with horizontal bars
  on the inner one. Partly folded, they slide off the fold.
  `presentationPlacement(_:)` can change this.
- **`.inspector`** is a trailing column on regular width and a sheet on compact.
- **Split View** is a 50/50 drag-to-side split on the inner display, with each
  app's controls on its outer edge. Apple hasn't published its size classes.
  There is no free drag-resize and no Stage Manager. New windows can only be
  created on the inner display.
- **Pinned video.** Another app's picture-in-picture can be pinned to the top,
  and the current app resizes vertically in real time. Partly folded, the video
  can take half the screen.
- **Compatibility mode depends on the SDK.** An iOS 26 SDK build runs at a
  familiar iPhone size: beside the status bar and camera when closed,
  letterboxed when open. iOS 27 SDK builds extend beside the status bar on the
  inner display. Only iOS 27.1 SDK builds go edge to edge with vertical bars.
- **New APIs (iOS 27.1):** `ReservedRegion`, `onHingeChange` (state and angle,
  "for effects, not layout"), `ArrangementView` (don't nest
  `NavigationSplitView` in it), `toolbarVerticalEdge`, `toolbarVerticalBehavior`,
  `ToolbarOverflowMenu`. `presentationPlacement` is available from iOS 27.0.

Where sources conflict, Phase 1 settles it: whether a portrait-locked app takes
part in Split View (the labs say it still gets the size-class changes, while the
tech talk says Split View needs a freely resizable app). Apple's documentation
settles `ArrangementView`: it needs iOS 27.1.

## 2. Where Motif stands today

| Area | Today | Effect on the Duo |
|---|---|---|
| Toolchain | CI is `macos-26` + `latest-stable`, which resolves to Xcode 26.6 at most → iOS 26 SDK | Compatibility mode. None of the regular-width problems below show until the SDK moves |
| Devices | `TARGETED_DEVICE_FAMILY = 1` (iPhone only) | Fine; the Duo is an iPhone |
| Orientation | `Info.plist` declares portrait only | Honored on the outer display, ignored on the inner one. Split View effect: **verify** |
| Scenes | Single `WindowGroup`, one `AppState`, no multiple-scenes key | One window only, which stays (decision 7). Split View means Motif beside another app |
| Navigation | `TabView` + two `NavigationStack`s driven by `puzzlesPath` / `gamesPath` | One stretched column on a 951 pt wide screen |
| View state | `SolveModel`, `GameViewModel`, `GameCollectionModel` selection and sheet drafts live in `@State` | Swapping containers or view types by size class would reset a session, unsaved moves or a selection. The layout must keep view identity (`AnyLayout`, one `NavigationSplitView`) |
| Analysis board | `GameView`: `min(width − margins − eval bar, height × 0.6)` | Outer: about 325 pt, 41 pt squares, assuming a 64 pt side bar (**verify**). Under the 44 pt minimum. Inner landscape: limited by height, with a wide empty strip |
| Other boards | Session (`ScrollView`), puzzle detail (`List` row) and `NewGameView` (`Form` row) take the full width with **no height cap** | At 27.1 SDK on the inner display the board is ~900 pt tall on a 669 pt screen. In a session, solving would need scrolling, which competes with piece drags |
| Custom bottom items | Analysis capsule (`.safeAreaBar`), Skip and `ResultCard` overlays, `Toast`, `SignInView` buttons (`.safeAreaInset`) | Don't move with vertical bars and ignore the fold |
| Toolbar labels | `AccountButton` and the Analysis and puzzle detail `…` menus have no title. `Select All` is text only | Avatar and menus may vanish or lose their title in overflow; `Select All` stays horizontal. Check each one |
| Tab bar | Hidden on puzzle detail, Analysis view and sessions; `.tabBarMinimizeBehavior(.onScrollDown)` | Check both on the vertical tab bar |
| Session | `fullScreenCover`; result card covers the lower 62% | On a wide screen the card covers the board needlessly |
| Banners | `libraryBanners()` on the session root but not on the pushed `PuzzleAnalysisView` | Likely existing bug: the "PGN copied." and "Saved to…" toasts, and save errors, don't show there. Confirm in Phase 2 |
| Sheets | Mostly `.large`; comment and destination sheets use `[.medium, .large]` | Centered on the inner display; side controls on the outer one |
| Adaptive code | `GeometryReader` in `GameView`, `BoardView`, `EvalBar`, `CollectionView`; `ViewThatFits` in `ResultCard`; no size-class reads; no `UIScreen` | Good base, because nothing reads the device directly |

## 3. Display configurations (mockup columns)

Every mockup cell is named `S<screen><state>·<config>`, e.g. `S15c·IL`.

| ID | Configuration | Size class (w × h) | Approx. points | Bars and notes |
|---|---|---|---|---|
| **O** | Closed, portrait | compact × regular | 466 × 678; 382 wide inside the 84 pt side bar. 457 × 678 with the case-gap setting | Vertical on the trailing edge. Height and width are both tight |
| **IL** | Open flat, wide (as opened) | regular × regular | 951 × 669; 867 wide inside the side bar | Vertical. Fold region 40 pt wide at x 455.5, reported but inactive when flat |
| **IP** | Open flat, tall | regular × regular | 669 × 951 | Horizontal; tab bar at the bottom. Fold region 40 pt tall at y 373.5 |
| **SV** | Split View half | compact × regular | 469 × 669 | Controls on the app's outer edge (84 pt); fold region is a 13.5 pt strip on the inner edge. Draw both sides |
| **PP** | Another app's video pinned on top | regular × regular flat; regular × compact bent | 669 × 606 flat; 669 × 465 bent | Pinned only with the phone tall. Horizontal bars. Height changes live |
| **FB** | Partly folded book (IL bent) | regular × regular + division | two pages either side of 455.5–495.5 | Controls go to the sides, none on the fold |
| **FT** | Partly folded portrait or tabletop (IP bent) | regular × regular + division | two halves either side of 373.5–413.5 | Controls on the stable bottom half; board on top |
| ~~ST~~ | Standing on its edges | as FB | as FB | **Dropped.** On the device it showed the same layout as FB (user, 2026-11-03), so it gets no column. Coverage-grid cells read "= FB" |
| **PD** | iPad, 11″ portrait and landscape | regular × regular | 834 × 1194 and 1194 × 834 | Expected to match IP and IL. Stage Manager windows use the same layouts as SV or IL |

Closed landscape isn't a configuration: the outer display stays portrait-only
(decision 2).

Fold and unfold transitions aren't static states. Each gets a three-frame
storyboard (§5, rule 7).

## 4. Screen and state inventory

Read from the code at `fd6675b`: 16 screens plus the shared banners,
**165 states**. Phase 2 re-checks this list, and any state found there that is
missing here is added before mockups start. Phase 3 added S05l and S16h and
redefined S07c (§8.4): **167 states**.

| # | Screen (file) | States |
|---|---|---|
| S01 | Launch / loading (`RootView`) | a blank · b loading · c first launch offline · d load error (Try Again / Sign Out) · e sign-out failed banner |
| S02 | Sign in (`SignInView`) | a empty (buttons disabled) · b filled · c keyboard up · d busy · e wrong password · f offline · g dev-account footer |
| S03 | Account sheet (`AccountView`) | a up to date · b syncing · c N waiting to upload · d offline (Sign Out disabled) · e offline, N waiting · f server error · g nothing to reset · h reset confirmation · i dev-account footer · j toast after reset · k error banner |
| S04 | Puzzles home (`PuzzlesHomeView`) | a populated (resume, review count, In progress chip) · b no session, nothing to review · c collections but no puzzles (Practice hidden) · d empty · e empty offline · f offline · g context menu · h swipe delete · i rename alert · j delete confirmation |
| S05 | Import puzzles sheet (`ImportView`) | a nothing yet · b parsed, existing collection · c parsed, new collection · d rejected rows · e all rows rejected · f several collections · g source error · h busy · i offline · j keyboard in editor · k Files picker · l opened from a collection (preselected) |
| S06 | Collection (`CollectionView`) | a stats card · b session in progress (Resume, Discard) · c ⋯ menu · d empty · e rename alert · f delete confirmation · g offline |
| S07 | Puzzle list (`PuzzleListView`) | a default · b searching · c scope applied with a query · d empty scope · e no search results · f no puzzles · g swipe actions · h delete confirmation · i offline |
| S08 | Puzzle detail (`PuzzleDetailView`) | a move puzzle at start · b stepping a solution · c several solution lines · d missing piece · e flagged · f ⋯ menu · g comment sheet · h delete confirmation · i offline |
| S09 | Session (`SessionView`, `PuzzleSolveView`, `MissingPieceSolveView`, `ResultCard`, `PiecePicker`) | a your move · b wrong move · c answer shown · d opponent replying · e promotion picker · f missing piece: tap square · g missing piece: choose piece · h missing piece: hint · i solved · j solved, several lines · k missed · l long result (card scrolls) · m session complete · n flagged · o offline |
| S10 | Puzzle analysis (`PuzzleAnalysisView` → scratch `GameContentView`) | a solution preloaded · b missing piece placed · c ⋯ menu · d Save as Game: existing collection · e Save as Game: new collection · f offline. Board states are as S15 |
| S11 | Games home (`GamesHomeView`) | a populated · b empty · c empty offline · d new collection alert · e context menu · f swipe actions · g rename alert · h delete confirmation · i offline |
| S12 | Game collection (`GameCollectionView`) | a browse · b search, no match · c + menu · d ⋯ menu · e edit mode, none selected · f edit mode with selection + bulk bar · g all selected · h reorder drag · i move/copy destination sheet · j rename alert · k delete collection confirmation · l delete selected confirmation · m empty · n empty offline · o offline · p edit mode offline · q share sheet |
| S13 | Import PGN sheet (`ImportPGNView`) | a nothing yet · b games read · c more than 5 games · d read errors · e source error · f busy · g offline · h keyboard · i Files picker |
| S14 | New Game sheet (`NewGameView`) | a standard start · b from FEN, empty · c valid FEN · d invalid FEN (board dimmed) · e keyboard · f offline |
| S15 | Analysis view (`GameView`) | a default with eval bar · b evaluation hidden · c engine lines · d engine starting · e comment card · f alternatives (≤ 3) · g alternatives expanded · h variations in the list · i no moves yet · j at start / at end · k promotion picker · l move context menu · m delete-from-here confirmation · n ⋯ game menu · o delete game confirmation · p unsaved, back alert · q unsaved, offline discard alert · r offline · s illegal-move problem · t unreadable PGN · u unreadable PGN offline · v densest case (engine lines + comment + alternatives) |
| S16 | Analysis sheets (`CommentSheet`, `GameDetailsSheet`) | a comment, empty · b comment with text (Remove Comment) · c comment at large detent · d comment keyboard · e details · f details keyboard · g share sheet · h game note |
| S17 | Library banners (`LibraryBanners`, `Toast`) | a offline · b offline, N waiting · c server error · d dismissible error · e toast |

S17 is drawn on three hosts: a list (S04), the session (S09) and the Analysis
view (S15). Other screens use the same safe-area inset and don't repeat it.

## 5. Mockup coverage rules

The full grid is 165 states × 9 configurations (1,485 cells). Many cells would
repeat an identical layout, so **every cell is either drawn, or marked with the
frame it equals, or marked n/a with a reason. No cell is left blank.** A
coverage grid tab on the canvas shows this, so "every state" can be checked at a
glance.

1. **Every state on O and IL.** These span compact and regular and are the two
   everyday poses. That's 330 frames.
2. **IP and SV.** Every screen's primary state (a), plus every state whose
   layout differs. Other cells show "= O" or "= IL".
3. **Board screens get the fold.** S08, S09, S10 and S15: every state whose
   layout changes on FB and FT.
4. **PP.** The primary state of each board screen, plus S09i and S15c, since
   the height changes live. Lists show "= IL".
   **PD.** Each screen's primary state. Other cells show "= IP" or "= IL".
5. **Transient overlays are drawn once per size class.** Alerts, confirmation
   dialogs, menus, context menus and system pickers get one compact frame (O)
   and one regular frame (IL), plus one FB frame showing how they clear the fold.
6. **System variants.** For each screen's primary state on O and IL: Dynamic
   Type AX5 and Reduce Transparency. Dark Mode is a canvas-wide toggle, so every
   frame has it.
7. **Transition storyboards.** Three frames each (before → mid → after) for:
   unfold mid-session (S09a), unfold in the Analysis view with unsaved moves
   (S15p), bend open to book in the Analysis view (S15c, IL → FB, where the
   board must shrink onto one page), fold with a sheet and keyboard open (S05j),
   and enter Split View from IL in edit mode (S12f). They show what persists
   (selection, path, scroll, draft text, sheet) and where focus lands.

Estimated total: ~600 frames (330 O/IL, ~100 IP/SV, ~60 FB/FT, ~10 PP, ~17 PD,
~65 variants, 15 storyboard).

### 5.1 Canvas conventions

- Built on the **Design artifact type** (live artboards on a canvas). Frames
  are generated from data: one component set and one table of screen, state and
  configuration, so a measured value changes every frame at once.
- Five canvases rather than one, since 580 live frames on one page is unlikely
  to stay usable: Analysis (S15, S10), Session and detail (S09, S08), Shell and
  homes (S01–S04, S11, S17), Lists (S06, S07, S12), Sheets (S05, S13, S14, S16).
  Each has a row per state and a column per configuration. Links go at the top
  of this file. Check performance on the Analysis canvas before building the rest.
- Frames are drawn at 1:1 points, with point sizes from Phase 1, not the
  estimates in §1.
- Device chrome: the outer frame shows the camera and side space, and the inner
  frame shows a dashed fold line. FB/FT shade the division region.
- Each frame gets chips for its size class (C/R × C/R), the bar edge (bottom /
  trailing / leading) and the SwiftUI container that produces it (e.g.
  `NavigationSplitView · .balanced`).
- Visual language: SF Pro (`-apple-system`), semantic system colors (`label`,
  `secondaryLabel`, `systemGroupedBackground`…), app tint `motifAccentStrong`,
  `motifAccent` for fills only, Liquid Glass approximated with backdrop blur and
  a specular edge on bars and controls only (never on content).
- Reuse the board, eval bar, move list and glass components from the earlier
  Motif canvases so the Duo frames match what has shipped.

## 6. iOS design standards checklist (every frame is checked)

Apple's "Designing for iPhone Duo" HIG page is the authority here. Phase 0 read
it in full on 2026-11-03 and corrected this list. It gives no point sizes and no
sheet or hit-target rules, so those items rest on the tech talk, the group lab
and the general HIG.

1. **System containers first.** `TabView`, `NavigationSplitView`,
   `NavigationStack`, `List`/`Form`, `.toolbar`, `.searchable`,
   `ContentUnavailableView`, `Menu`, `confirmationDialog`, `alert`, `sheet`.
   Nothing custom where a system piece exists.
2. **Size classes, not devices.** No idiom or orientation checks and no fixed
   screen widths. Use `horizontalSizeClass`, container size, `ViewThatFits`
   and `AnyLayout`. Don't override size classes.
3. **Same app in every pose.** Same hierarchy, controls and functionality on
   both displays. No feature depends on a pose.
4. **Safe areas per edge, plus reserved regions.** Nothing interactive sits under
   the camera, the Dynamic Island or the fold division. Board squares count as
   discrete controls, so a board stays on one side of a division.
5. **Bars.** Navigation titles are large on top-level lists and inline on detail
   screens. Every toolbar item has a title and a symbol, and text buttons are
   rare because they stay horizontal. Custom bars check `toolbarVerticalEdge`.
   Order items with Back or Close at the top, then prominent actions, and group
   with `ToolbarItemGroup` rather than manual spacing. Overflow runs bottom to
   top, so frequent and status-bearing items get a higher
   `ToolbarItemVisibilityPriority`. Ellipsis means overflow only: custom overflow
   actions move into `ToolbarOverflowMenu`, and other menus get a distinct symbol.
   That covers the Analysis and puzzle detail `…` menus. Each screen picks a
   `ToolbarVerticalCompressionBehavior`: navigation screens keep the tab bar, and
   task screens minimize it to keep their actions.
6. **Hit targets ≥ 44 × 44 pt.** That includes board squares: a board of at
   least 352 pt. Where a frame can't reach that, it shows the trade-off and
   records the decision. The move rows (34 pt), alternatives (36 pt) and solution
   chips (36 pt) are already under this on iPhone, so Phase 3 lists them too.
7. **Layout margins** are 16 pt compact and 20 pt regular. On regular width,
   text and forms stay within the readable content width (~672 pt) and don't
   stretch.
8. **Sheets.** ✕ in `cancellationAction`, ✓ in `confirmationAction`. Detents for
   short content on compact width. Centered form sheet on the inner display, and
   nothing resting on the fold.
9. **Dialogs and menus.** Presented by the system, driven from state rather than
   anchored to a menu item that may have moved to overflow.
10. **Typography and Dynamic Type.** Text styles only, up to AX5, with no key
    label truncated. Board coordinates and move numbers keep `monospacedDigit`.
11. **Color and contrast.** Semantic colors, text contrast ≥ 4.5:1 in light and
    dark, and state never shown by color alone.
12. **Liquid Glass** on navigation and controls only, with a legible fallback for
    Reduce Transparency and Increase Contrast. Corners concentric with the
    display where a card sits near one (`ConcentricRectangle`).
13. **Motion and haptics.** Existing selection and error haptics stay. Layout
    changes on fold and unfold animate with the system, with no custom
    transitions.
14. **Accessibility.** VoiceOver order stays logical across two columns and
    across the fold (board, then moves, then controls). Every accessibility
    identifier the UI tests use survives each layout.
15. **Continuity.** Folding or unfolding never loses navigation, selection, a
    draft, an open sheet, a running session or unsaved moves.
16. **Folding.** Prefer containers that adapt by themselves, including
    `ArrangementView` (split or overlay) for layouts shaped like an
    `HStack`/`VStack` or a `ZStack`. Keep navigation containers outside it. Grids
    use an even column count. Fold changes are small adjustments that keep
    controls visible, never an extreme rearrangement. Custom layouts read
    `ReservedRegion` frames, which already include the region's margins.

## 7. Design direction to test in the mockups

These are starting points, not decisions. Each one is drawn and checked
against §6, and the ones the user must choose are in §10.

**App shell.** One `NavigationSplitView` in each tab at every size, rather than
choosing a container by size class. It collapses to a stack on compact by
itself, so view state survives folding (§6.15). `puzzlesPath` and `gamesPath`
keep driving the detail stack.
- *Tabs:* keep the system tab bar, which goes to the side on O and IL and the
  bottom on IP. With only two tabs, a tab sidebar plus a split view sidebar would
  add an empty column. `.sidebarAdaptable` is drawn on S04a·IL for comparison.
- *Puzzles:* collections (with Practice) | collection overview / puzzle list |
  puzzle detail.
- *Games:* collections | game list | Analysis view. With a game open the split
  collapses to the detail (`.prominentDetail`), so the board gets the width.
- *Avatar:* gets a title for overflow. Check it stays visible in the side bar.

**Lists** (S04, S06, S07, S11, S12) are split view columns on regular width.
Swipe actions, context menus and edit mode stay unchanged. The S12 bulk bar stays
in `.bottomBar`, so the system can move it.

**Board layout rule (S08, S09, S10, S15).** One rule from the container shape,
not one layout per pose: wider than tall is two panes, taller than wide is
stacked, and an `AnyLayout` switches between them so state survives. A division
only moves the split onto the fold. All four screens cap the board by height.

**Analysis view on O** uses option A (decision 5; mockups linked at the top). The
system side bar stays, with Flip and Engine lines in it and ‹ › beside the move
list. Assuming a 64 pt side bar, the board is 348 pt (43.5 pt squares) with the
eval bar, 4 pt short of the minimum, with 5 move rows. It is 370 pt (46 pt
squares) without the eval bar and in sessions. With engine lines on, all 3 lines
fit and replace the move list, since there isn't room for both. Option B (vertical
bars off) gave a 412 pt board but only 2 move rows and 1 visible engine line.

**Analysis view on the other configurations:**
- *IL:* board and eval bar on the leading side at full height. The trailing
  column holds engine lines, comment card, alternatives and the move list, with
  the ‹ › capsule at its bottom. Flat, the board can cross the fold line.
- *IP / SV:* stacked, with today's 0.6 height cap relaxed so the board fills the
  width.
- *FB:* the board shrinks onto one page (about 440 pt), moves and controls on
  the other.
- *FT:* board on the top half, moves and controls on the bottom half.
- *PP:* wider than tall, so two panes, with the board following the height.

**Puzzle detail and session (S08, S09)** use the same rule. On two panes the
prompt, Skip, picker and result card go in the trailing pane and stop covering
the board. On O the board must fit without scrolling, with the result card still
rising over it.

**Sheets (S03, S05, S10d, S13, S14, S16)** keep system placement: side controls
on O, centered on the inner display, off the fold when bent. S03 has one toolbar
button, so it can opt out of the vertical bar. The S14 board preview gets a height
cap and sits beside the FEN field when the width allows.

**Sign in and loading (S01, S02)** are a centered column at readable width on
regular width. With the keyboard up on IL, the fields stay above the keyboard.
The S02 buttons need to sit clear of the side bar on O.

**iPad** reuses the regular-width layouts with no iPad-specific screens. The app
has no idiom checks to change. It needs the iPad device family, all four iPad
orientations, an iPad simulator in CI, and iPad App Store screenshots before a
public release.

## 8. Investigation phases

**Phase 0 — Toolchain.** The Mac phase is over, and no Mac is needed for this:
the `xcode-27` GitHub runner (image 20261026, macOS 27, preview) has Xcode 27.1
as its default and an iPhone Duo simulator on the iOS 27.1 runtime. `macos-26`
stops at Xcode 26.6. Add a manual workflow on `xcode-27` that pins 27.1, and
confirm the app, including Stockfish, builds there. Upload that build to
TestFlight for the user's iPhone Duo. Check whether `simctl` can close, open and
fold the Duo headlessly, since Device Hub is a GUI. If it can't, CI covers what
it can and the device covers the rest. Read the full HIG page in a browser and
update §6. The deployment target stays 26.1, and 27.1 APIs are gated with
`if #available(iOS 27.1, *)`.

**Phase 1 — Measure.** Add a temporary layout probe that shows the container
size, size classes, safe-area insets per edge, `toolbarVerticalEdge` and division
region frames. TestFlight builds are Release, so it can't sit behind `#if DEBUG`:
it goes behind a TestFlight-only check and is removed after this phase. The user
screenshots it on the device in each configuration in §3, and fold poses are
measured there. Also record sheet placement and width, the keyboard frame on O
and IL, Split View and pinned-video sizes, and which toolbar items reach overflow.
Settle the conflicts at the end of §1. Results go in a table here, and §3 and the
§7 board numbers get updated. Mockups use these numbers.

### 8.1 Phase 0 and Phase 1 results (2026-11-03)

**Toolchain.** The app, including Stockfish, builds on `xcode-27` with Xcode 27.1
and uploads to TestFlight (build 23, with the probe). `ios-testflight.yml` takes an
`xcode_27` input rather than a second workflow, so build numbers stay in one
sequence. The layout probe (`LayoutProbe.swift`, the `layout_probe` input, the
`ios-duo-probe` workflow and script) was removed once Phase 1 was done; it is in
the history of the `iphone-duo-phase-one` branch if a later phase needs it.

**Simulator.** `simctl` has no fold or pose command. Powering the displays with
`simctl io screenConfig` crashes the system shell, and the inner display came back
black. The outer display can be captured in CI with `--display=1`. The
community tool `duoctl` claims headless hinge control through private
interfaces; untried. Phase 1 was measured on the user's iPhone Duo (44
screenshots named `<config>-<screen>.png`, e.g. `FB-game.png`, kept outside the
repo).

**Measurements (device, Xcode 27.1 SDK build).**

| Config | Window (pt) | Size class | Safe area insets T / L / B / R | Bars | Reserved regions |
|---|---|---|---|---|---|
| O | 466 × 678, @3x | C × R | 0 / 0 / 34 / 84 | trailing | camera 37 × 37 at (399.7, 29.3); side status 84 × 174 at (382, 0) |
| O, case gap on | 457 × 678 | C × R | 0 / 0 / 34 / 84 | trailing | as O |
| IL | 951 × 669, @3x drawn at 2.8 (1878 × 2670 px) | R × R | 0 / 0 / 34 / 84 | trailing | division 40 × 669 at x 455.5, margins 20 left and right, inactive when flat; camera 62 × 39.5 at (658.6, 22.4), inactive |
| IP | 669 × 951 | R × R | 82 / 0 / 34 / 0 | horizontal, tab bar at bottom | division 669 × 40 at y 373.5, margins 20 top and bottom |
| FB | as IL | R × R | as IL | trailing | division active |
| FT | as IP | R × R | as IP | horizontal | division active |
| SV, left | 469 × 669 | C × R | 0 / 84 / 34 / 0 | leading | division 13.5 × 669 at x 455.5 (the inner edge) |
| SV, right | 469 × 669 | C × R | 0 / 0 / 34 / 84 | trailing | division 13.5 × 669 at x 0 |
| PP, flat | 669 × 606 | R × R | 0 / 0 / 20 / 0 | horizontal | division 669 × 40 at y 110.8, inactive |
| PP, bent | 669 × 465 | R × C | 0 / 0 / 20 / 0 | horizontal | division strip 669 × 9.8 at the top edge |

Settled:
- **Inner display: 951 × 669 pt.** The panel is 1878 × 2670 px, so iOS draws at
  3x and scales down by 2.8. Mockups use 951 × 669.
- **Split View: a portrait-only app takes part.** No `Info.plist` change is needed
  for decision 3. Each half is compact width, so it gets the O layout with the
  bars on its outer edge.
- **Pinned video** works only with the phone tall, and pins above the app (IP),
  not beside it. Flat leaves 669 × 606 (regular height). Bent leaves the bottom
  half, 669 × 465, which is **regular × compact**: the only regular-width,
  compact-height configuration.
- **Picture in picture** that isn't pinned floats over the app without resizing it.
- **Standing on its edges** matched FB (decision 8).
- **Continuity:** unfolding in a game kept the game and the selected move.

Sheets and keyboard:
- **O:** the comment sheet (medium) is 450 × 390, 8 pt from each edge, with ✕ and
  ✓ in the side bar. With the keyboard up it grows to 450 × 670, and the keyboard
  is 313 pt tall.
- **IL:** the comment sheet is centered, 653 pt wide, with horizontal ✕ and ✓.
  The keyboard is split at 289 pt tall and the sheet grows to the top.
- **IP:** 653 pt wide, but **compact width** inside the sheet.
- **FB:** the sheet moves onto the left page (459.7 pt wide). **FT:** it sits
  below the fold.
- **Account sheet:** side ✕ on O, centered on IL.

Toolbars: on O and IL the avatar, +, ‹ and ⋯ all stay in the side bar, and
nothing went to overflow. The game ⋯ menu opens beside the side bar.

Board today (Analysis view, eval bar on): O 299 pt (37 pt squares), IL 293 pt,
IP 462 pt, SV 293 pt, PP flat 264 pt, PP bent about 180 pt. **On FB and FT the
board crosses the active fold.**

Effect on §7: the side bar is 84 pt, not 64 pt. Option A on O gives a 328 pt
board with the eval bar (41 pt squares) and 350 pt without it and in sessions.
With the case gap these are 319 pt and 341 pt. All are under the 352 pt minimum.
Layout reads container size, so the case gap needs no special code; frames on O
are drawn at 466 pt with one 457 pt check per board screen.

**Phase 2 — Capture today.** *Done 2026-11-05 (§8.2, §8.3).* Run every screen × configuration and screenshot it,
twice, by extending `scripts/ios-screenshot.sh`:
1. the current build (iOS 26 SDK, compatibility mode);
2. the same code built with the 27.1 SDK, with no layout changes.

This uses the existing `MotifRoute` launch routes (`account`, `board`,
`collection`, `game-add`, `game-collection`, `game-comment`, `game-details`,
`game-eval`, `game-new`, `game-select`, `game-unreadable`, `game-variation`,
`game:…`, `import`, `puzzle-detail`, `puzzle-list`, `puzzle-list-empty`,
`result:…`, `result:failed`, `session:…`, `session:missing`, `signin`) plus
`MotifOffline`. States with no route yet get a debug route added in this phase
(sign-in error, empty homes, alerts, engine lines on, alternatives expanded,
promotion picker, session complete…) so that Phase 4 frames and the final
screenshot tests line up one to one. System pickers and transient menus are
captured by UI test taps.

### 8.2 Phase 2 method (2026-11-03)

`scripts/ios-screenshot.sh` takes one route per launch, which can't reach most
states. Phase 2 uses a UI-test capture suite instead:

- **`MotifUITests/DuoCaptureTests`** has one test per screen. Each state launches
  fresh, gets there through its route, a fixture and taps, and saves one screenshot
  named for its cell (`S15c`, and `S17a-S04` for a banner on a host). It is skipped
  unless the runner sets `MOTIF_CAPTURE=1`, so the PR check doesn't pay for it.
  `MOTIF_CAPTURE_ONLY` narrows a run (`S08,S15`, or `primary`).
- **Launch fixtures** (`App/CaptureFixture.swift`, Debug only):
  `-MotifFixture seed=games,engine,lines`. Seeds (`empty`, `collections`,
  `progress`, `games`, `solve`), account and backend faults (`hang-user`,
  `hang-load`, `fail-load`, `fail-signin`, `hang-writes`…), store state
  (`pending=N`, `status=syncing|error`, `error`, `notice`, `offline-first`), the
  scripted engine, the Analysis view toggles, `problem`, `slow-reply`, and
  prefilled import texts. New routes: `puzzle-detail:<id>`, `session:<collection>`,
  `result:<collection>`, `game:<id>`, `games`. These line up one to one with the
  Phase 4 frames and become the D09 screenshot tests.
- **Poses.** `duoctl` (third party, private simulator interfaces) sets the hinge
  and rotation headlessly: O = closed, IL = open + landscape, IP = open + portrait,
  FB = half + landscape, FT = half + portrait. Split View and pinned video have no
  simulator control, so SV and PP come from the device (below). iPad (PD) isn't
  captured: the app is iPhone-only until D11, so an iPad shows the iPhone app.
- **Two builds.** `ios-duo-capture.yml` builds the app with Xcode 26 (`macos-26`,
  iOS 26 SDK) and the app plus the suite with Xcode 27.1 (`xcode-27`). Each pose
  runs as its own job on the 27.1 Duo simulator. The iOS 26 run swaps its app in
  under the same test runner. Compatibility mode shows an iPhone-sized window on
  the inner display, so the iOS 26 build takes every state on O and IL and the
  primary states on IP, FB and FT.
- Not capturable from XCTest: S12h holds a reorder drag mid-gesture, so its frame
  shows edit mode with the handles instead.

**Device captures (2026-11-04).** TestFlight build 25 (Xcode 27.1) on the user's
iPhone Duo, in Split View beside Discord (S04a beside the App Store), dark mode,
the user's own library: screenshots named `SVL-<cell>.png` / `SVR-<cell>.png`
(Motif on the left or right half), kept outside the repo with the Phase 1 set, 36
in all. Cells on both sides: S03a, S04a, S05a, S06a, S07a, S08a, S09a, S09i, S10a,
S11a, S12a, S12f, S14a, S15a, S15c, S15e, S16a, S16d. Pinned video (PP) isn't
captured (decision 9).

### 8.3 Phase 2 results (2026-11-05)

Run [41938432623](https://github.com/darianthedy/motif/actions/runs/41938432623)
at `4545c60`: 175 states (165 in §4 plus S17 on three hosts) in each pose on the
27.1 SDK build, and on O and IL on the iOS 26 SDK build; the iOS 26 build's primary
states on IP, FB and FT. 1,273 simulator screenshots plus the 36 Split View device
shots, kept outside the repo (`iphone-duo-motif/simulator/sdk<N>-<pose>/<cell>.png`,
with each pose's `pose-before.json` and `unreached.txt`). The workflow's artifacts
hold the same files for 90 days. Every capture is in light mode; the device shots
are dark.

- **O 27**: 173 reached, 2 not reached; pose 0.0°, cover screen, portrait, [466.0, 678.0] pt
- **IL 27**: 172 reached, 2 not reached; pose 180.0°, inner screen, landscape, [951.0, 669.0] pt
- **IP 27**: 174 reached, 1 not reached; pose 180.0°, inner screen, portrait, [669.0, 951.0] pt
- **FB 27**: 173 reached, 2 not reached; pose 90.0°, inner screen, landscape, [951.0, 669.0] pt
- **FT 27**: 174 reached, 1 not reached; pose 90.0°, inner screen, portrait, [669.0, 951.0] pt
- **O 26**: 168 reached, 2 not reached; pose 0.0°, cover screen, portrait, [466.0, 678.0] pt
- **IL 26**: 171 reached, 1 not reached; pose 180.0°, inner screen, landscape, [951.0, 669.0] pt
- **IP 26**: 18 reached, 1 not reached; pose 180.0°, inner screen, portrait, [669.0, 951.0] pt
- **FB 26**: 18 reached, 1 not reached; pose 90.0°, inner screen, landscape, [951.0, 669.0] pt
- **FT 26**: 18 reached, 1 not reached; pose 90.0°, inner screen, portrait, [669.0, 951.0] pt
- **SV device**: 18 cells, both halves

Not reached, and why:
- **S07c, every pose:** the search scopes never show. With the search field active
  there is no scope bar on any size, with or without the keyboard. A Phase 3 finding.
- **S08g, IL and FB:** the puzzle detail board is as wide as the screen (867 pt) and
  taller than it, so the comment row can't be scrolled into reach. A Phase 3 finding
  (the §2 "no height cap" row).
- **S09o on O 27 and S17b-S09 on O 26:** the session route didn't open on that
  launch, twice. A launch race seen in the existing UI tests too; the other build's
  frame shows the state.
- **S10a on the iOS 26 build's inner poses:** XCTest's tap on Analyze doesn't land
  in the letterboxed compatibility window. The window is the closed screen's, so the
  cell equals O 26.
- **S12h** shows edit mode with its handles, since a drag can't be held mid-gesture.

What the captures show (input to Phase 3):
- **iOS 26 SDK (today's build):** O is the iPhone layout beside the side bar. Every
  inner pose shows the same iPhone-sized window letterboxed in black, with an expand
  button, so the inner display gains nothing until the SDK moves.
- **27.1 SDK, no layout changes:**
  - *O* matches §8.1: the side bar holds the toolbar and tabs, and the Analysis board
    is 328 pt with the eval bar.
  - *IL and FB* look the same: the app ignores the fold. The puzzle detail and session
    boards fill the width and run off the bottom, so the result card covers most of
    the board and the solution, status and comment rows are out of reach. The Analysis
    board is capped by height (293 pt) with wide empty strips beside it, and the
    engine lines, comment card and controls stretch across the full 867 pt. Lists
    stretch to the full width.
  - *IP and FT* look the same: horizontal bars and a bottom tab bar. Boards fill the
    669 pt width and cross the fold line on FT.
  - *Sheets* sit centered on the inner display. The New Game preview board fills the
    sheet, which pushes the FEN field below the fold (S14c–e needed scrolling).
  - Toolbar items in the side bar and menu items lose their accessibility
    identifiers, so the suite finds them by title. D09 has to keep that in mind
    (§6.14).
- **Split View (device):** each half gets the O layout with the bars on Motif's
  outer edge, including the S12f bulk bar and the tab bar. The keyboard (S16d) spans
  both halves.

Coverage grid. ✓ captured and reached · ✗ captured, state not reached · = O the
letterboxed compatibility window, same as O 26 · – not captured by design (the
iOS 26 build's non-primary states on IP, FB and FT; Split View's non-primary
states; S17 on the device). PP isn't captured (decision 9), and PD waits for D11.

| State | O 27 | IL 27 | IP 27 | FB 27 | FT 27 | O 26 | IL 26 | IP 26 | FB 26 | FT 26 | SV device |
|---|---|---|---|---|---|---|---|---|---|---|---|
| S01a | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ | ✓ | ✓ | – |
| S01b | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | – | – | – | – |
| S01c | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – | – | – |
| S01d | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – | – | – |
| S01e | ✓ | – | ✓ | ✓ | ✓ | – | – | – | – | – | – |
| S02a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – |
| S02b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S02c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S02d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S02e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S02f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S02g | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S03a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S03b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S03c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S03d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S03e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S03f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S03g | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S03h | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S03i | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S03j | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S03k | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S04a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S04b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S04c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S04d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S04e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S04f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S04g | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S04h | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S04i | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S04j | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S05a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S05b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S05c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S05d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S05e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S05f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S05g | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S05h | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S05i | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S05j | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S05k | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S06a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S06b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S06c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S06d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S06e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S06f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S06g | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S07a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S07b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S07c | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | = O | – | – | – | – |
| S07d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S07e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S07f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S07g | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S07h | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S07i | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S08a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S08b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S08c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S08d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S08e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S08f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S08g | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✓ | – | – | – | – |
| S08h | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S08i | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S09b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09g | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09h | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09i | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | ✓ |
| S09j | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09k | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09l | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09m | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09n | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S09o | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S10a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | = O | = O | = O | ✓ |
| S10b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S10c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S10d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S10e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S10f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S11a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S11b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S11c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S11d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S11e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S11f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S11g | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S11h | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S11i | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S12b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | ✓ |
| S12g | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12h | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12i | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12j | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12k | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12l | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12m | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12n | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12o | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12p | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S12q | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S13a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – |
| S13b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S13c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S13d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S13e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S13f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S13g | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S13h | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S13i | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S14a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S14b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S14c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S14d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S14e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S14f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S15b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | ✓ |
| S15d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | ✓ |
| S15f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15g | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15h | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15i | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15j | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15k | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15l | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15m | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15n | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15o | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15p | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15q | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15r | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15s | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15t | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15u | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S15v | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S16a | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S16b | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S16c | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S16d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | ✓ |
| S16e | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S16f | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S16g | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S17a-S04 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – |
| S17a-S09 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – |
| S17a-S15 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – |
| S17b-S04 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S17b-S09 | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | – | – | – | – |
| S17b-S15 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S17c-S04 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S17c-S09 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S17c-S15 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S17d-S04 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S17d-S09 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S17d-S15 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S17e-S04 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S17e-S09 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |
| S17e-S15 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – |

**Phase 3 — Audit.** *Done 2026-11-05 (§8.4).* For each captured cell, list where it breaks the §6
checklist or wastes the screen. Output is a findings table (screen · config ·
issue · checklist item · severity), appended to this file, starting from the §2
rows. Re-check the §4 inventory against the code at the same time.

### 8.4 Phase 3 results (2026-11-05)

**Method.** Every 27.1 SDK capture from §8.3 was put on contact sheets, one row
per state. Board screens (S08, S09, S10, S15) were read in all five simulator
poses, and the other screens on O, IL and IP. FB matched IL and FT matched IP
pixel for pixel apart from the fold, as §8.3 found, so FB and FT were checked
only where something sits on the fold. Split View was read from the 36 device
shots, and the iOS 26 build from its primary states. Points below are measured
off the screenshots at the §8.1 scale.

**Severity.** **High**: a task can't be finished, or a control or content can't
be reached, without a workaround. **Medium**: breaks a §6 rule in a way users
will notice. **Low**: polish, or wasted space that doesn't block anything.

#### §2 rows, checked against the captures

- **Toolchain:** confirmed. The iOS 26 build letterboxes an iPhone window on every
  inner pose (on IP it is scaled to about half size, with an expand button). On FB
  the window sits on the right page.
- **Orientation:** confirmed. Portrait-only is honored on O and ignored on the
  inner display.
- **Navigation:** confirmed. One stretched column at 867 pt on IL, 669 pt on IP.
- **View state:** not checkable from still captures. The device kept the game and
  move on unfold (§8.1); the §5 rule 7 storyboards cover the rest.
- **Analysis board:** confirmed. O 328 pt with the eval bar, IL and FB 293 pt
  between two empty strips.
- **Other boards:** confirmed, and worse than expected. See F1–F4.
- **Custom bottom items:** confirmed. Skip, the result card and the Analysis capsule
  ignore the fold, and the toast collides with the capsule (F24).
- **Toolbar labels:** confirmed. Nothing went to overflow. `Select All` stays a
  horizontal text button at the top of the content (F30).
- **Tab bar:** the vertical tab bar on O and IL shows symbols with no titles. The
  bottom tab bar on IP has titles (F31).
- **Session result card:** confirmed (F5).
- **Banners on `PuzzleAnalysisView`:** **confirmed bug.** S10f shows no offline pill
  where S15r does (F14).
- **Sheets:** confirmed. Centered 653 pt on IL, side ✕/✓ on O. See F17–F20.
- **Adaptive code:** holds. Nothing broke because of a device check.

#### Findings

Each row names the slice (§9) expected to fix it.

| # | Screen | Config | Issue | §6 | Sev. | Slice |
|---|---|---|---|---|---|---|
| F1 | S08 all states | IL, FB | Puzzle detail board is 867 pt wide and taller than the 669 pt screen. Only ranks 8–3 show. Solution chips, line picker, Status/Motif/Rating/Comment rows are off screen; S08g couldn't even be scrolled to | 4, 7 | High | D05, D06 |
| F2 | S09 all board states, S17a–e on S09 | IL, FB | Session board is 867 pt and runs off the bottom. Ranks 2–1 and the status pill are hidden until the board auto-scrolls (S09c then hides ranks 8–5). Solving needs scrolling, which competes with piece drags | 4, 6 | High | D05, D06 |
| F3 | S08, S09, S15, S10, S16 boards | FB | The board crosses the active fold division (x 455.5–495.5) on every board screen. On S08/S09 it spans both pages; on S15/S10 the 293 pt board straddles the fold at x ≈ 266–578 | 4, 16 | High | D07 |
| F4 | S08, S09, S15, S10 boards | FT | The board crosses the fold division (y 373.5–413.5). The S09k promotion picker and S09g piece picker sit on or beside the fold | 4, 16 | High | D07 |
| F5 | S09i–l | O, IL, FB, IP, FT | The result card covers 40–75 % of the board. On IL it is 867 pt wide, with the Continue button about 400 pt wide and S09l's text in lines of ~140 characters | 7 | Medium | D06 |
| F6 | S15 all states | IL, FB | Board capped at 293 pt (37 pt squares) by height, with ~290 pt of empty space on each side. Engine lines, comment card, move list and capsule stretch to 867 pt: white and black moves sit ~250 pt apart, and alternatives chips float at the far right, away from the move they belong to | 6, 7 | High | D05 |
| F7 | S15c, S15e–h, S15v | O | With engine lines or alternatives on, the 678 pt height leaves 0–1 move rows visible. S15v (densest) shows no move rows at all, and the comment card is half under the capsule | 7 | Medium | D05 |
| F8 | S15g | O | Expanded alternatives column overlaps the board's bottom-right squares | 4 | Medium | D05 |
| F9 | S15 all, S10 all | O | Board 328 pt (41 pt squares) with eval bar, as accepted in decision 5. Move rows 34 pt and alternatives 36 pt are under 44 pt on every pose | 6 | Low (accepted) | D05 |
| F10 | S08, S09 | O | Board runs edge to edge (382 pt, 0 pt leading margin) next to the side bar, so a-file squares sit against the display corner | 7 | Low | D05 |
| F11 | S08, S09 | IP, FT | Board fills the 669 pt width edge to edge (84 pt squares) and pushes the status pill and solution rows to the bottom. On S08 the floating step controls cover the Status row | 7 | Medium | D05, D06 |
| F12 | S15k, S09e | all | Promotion picker is an overlay card centered on the board, covering the squares around the promotion square; its four choices are ~40 pt | 6 | Low | D05 |
| F13 | S15t, S15u, S01c, S04d, S11b, S12m and other empty states | IL | `ContentUnavailableView` descriptions run on one line up to ~600 pt; S15t's PGN box stretches to 867 pt | 7 | Low | D03, D04 |
| F14 | S10f | all | **Bug:** offline pill missing in Puzzle Analysis. `libraryBanners()` isn't applied to the pushed `PuzzleAnalysisView`, so toasts and save errors also don't show (§2) | 15 | Medium | D08 |
| F15 | S04j, S06f, S07h, S08h, S11h, S12k, S12l, S15m, S15o, S03h | O, IL | Confirmation dialogs show as popovers anchored to the wrong place: the title or top-left of the content (S15m/o, S08h, S06f, S12k/l on O), the stats card, or outside the Account sheet (S03h on IL). On IP the same dialogs anchor to the bottom | 9 | Medium | D02 |
| F16 | S08f, S10c, S15n, S06c, S12d | all | The ellipsis menus hold custom actions (Copy FEN/Delete, Save/Edit Details/Copy PGN…, Rename/Delete) rather than overflow | 5 | Medium | D02 |
| F17 | S10d, S10e | O, IL, IP | Save as Game is a `.large` sheet holding one or two rows, about 85 % empty | 8 | Low | D08 |
| F18 | S14a–f | IL, IP | New Game preview board fills the 653 pt sheet (~610 pt), so the FEN field, its error and the offline note are below the fold of the sheet. In S14b on IL the segmented control has scrolled away | 7, 8 | High | D05, D08 |
| F19 | S05i, S14f | O, IL | Offline: ✓ is disabled, but the "importing needs a connection" note is below the visible area of the sheet, so the reason isn't shown | 3, 11 | Medium | D08 |
| F20 | S16a–c | all | The comment sheet's text editor is translucent: board pieces show through the blurred field behind the text | 12 | Medium | D08 |
| F21 | S02c | O, IL | With the keyboard up, the Sign In button (in `.safeAreaInset`) rises over the Password field and hides it | 4 | High | D08 |
| F22 | S02 all, S04, S06, S07, S11, S12 lists, S03 | IL | Sign-in form and buttons, lists, the stats card and Solve rows stretch to 867 pt, past the ~672 pt readable width. Below them, half the screen is empty: no split view | 7 | Medium | D02–D04, D08 |
| F23 | S07c, S07d | all | Search scopes show only once a query is typed. With an empty search there is no scope bar, so a scope (Flagged…) can't be picked or left without typing (S07c unreachable) | 1, 3 | Medium | D03 |
| F24 | S17e on S15, S17e on S09 | O, IL, IP | The "PGN copied." toast sits on top of the Analysis capsule (over ‹/›) and next to Skip in a session | 4 | Medium | D08 |
| F25 | S17c on S09 | O | The error banner pushes the session down; Skip then overlaps the status pill and truncates "Find the best move" | 10 | Medium | D08 |
| F26 | S17a–e | IL | Banners stretch the full 867 pt across the board column and side strips | 7 | Low | D08 |
| F27 | S09m | IL, FB, IP, FT | Session complete: stat tiles and the Done button stretch to the full width (Done ~830 pt on IL). On FT the "Session Complete" title sits on the fold | 7, 16 | Low | D06 |
| F28 | S06e, S07c | O | ~~A solid black circle replaces a toolbar item at the top of the side bar while an alert or search field is active~~ Simulator only: on the device the side bar keeps ‹ and ⋯ (rename) and ‹, + and ⋯ (search) (2026-11-06) | 5 | Dropped | — |
| F29 | S08g, S10d, S12i, S16a | O | Sheets at medium detent cover the lower half of the board, so the move being commented on is hidden | 8 | Low | D08 |
| F30 | S12e–i, S12l, S12p | O, IL, SV | Edit mode: `Select All` / `Deselect All` is a text button at the top of the content; bulk-bar items (Move, Copy, Export, Delete) are symbols with no titles in the side bar and bottom bar | 5 | Medium | D04 |
| F31 | all tab screens | O, IL, SV | Vertical tab bar shows symbols only (puzzle piece, board); titles appear only on IP's bottom tab bar | 5 | Low | D02 |
| F32 | S04, S11 | O, IL | The account avatar sits at the top of the content beside the title, while + is in the side bar. Phase 1 recorded the avatar in the side bar; it isn't | 5 | Low | D02 |
| F33 | S08a, S09a | SV left | The board's right edge runs into the 13.5 pt division strip on the inner edge. Confirmed on the device (2026-11-06): the board's h-file is flush with Motif's inner edge, with no margin, while the side bar has 59 pt on the outer edge | 4, 7 | Medium | D07 |
| F34 | S16d | SV | The split keyboard spans both halves of Split View (system behavior; the sheet is unaffected) | — | Info | — |
| F35 | S02, S03, S04, S15 captions | all | Secondary text (sign-in tagline, placeholders, "White to move", Detail values "Unknown/Unrated") is light gray on gray; check ≥ 4.5:1 in the mockups | 11 | Low | D10 |
| F36 | all | IP, FT | The 82 pt top inset plus horizontal bars leave the IP title inline and small; top-level lists keep large titles | 5 | Info | — |

#### Capture issues to fix before D09

These are problems with the capture run, not with the app. The D09 screenshot tests
need them fixed so each cell shows its state.

- **S01b on IL** shows the offline screen (S01c), and **S01d on IL** shows sign-in:
  the fixture raced the launch.
- **S02b on IP** shows empty fields with the keyboard up.
- **S03j on O and IL:** the reset toast isn't on screen (it is on IP). Either the
  toast is hidden behind the Account sheet or the shot was early. Not checked on the
  device, since that would reset the user's real progress. The toast is an overlay
  on the sheet's own content, so it is most likely a timing issue; D09 checks it
  with the `notice` fixture rather than a real reset.
- **S05k and S12q on IL** (Files picker, share sheet) were captured before their
  content loaded, and S05k on O is blank.
- **S09m** shows 0 solved / 0 missed: the fixture finishes the session without
  recording results.
- **S07c** can't be reached as written (F23). It is redefined below.

#### §4 inventory re-check

The code at this branch matches §4 (Phase 2 only added capture hooks), with these
changes:
- **S05l (new):** Import Puzzles opened from a collection (`ImportView(collectionId:)`
  via the collection ⋯ menu's Import Into Collection…), with the collection
  preselected. Layout = S05b.
- **S16h (new):** game note: the comment sheet on the game itself (⋯ → Edit Game
  Note), titled with the game name. Layout = S16a/b.
- **S07c redefined:** "scope applied with a query", since scopes only show with
  search text (F23). The mockups draw the intended state: scopes reachable with
  no query.
- **S12h** stays "edit mode with handles" (§8.2).

The inventory is now **16 screens, 167 states**.

#### What this changes for Phase 4

- **Analysis canvas first (as planned)**, with F3, F6 and F7 as the main problems.
  The IL board must grow past 293 pt into one page or a column (§7), and the move
  list must stop stretching.
- **Session and puzzle detail** (F1, F2, F5, F11) need a height-capped board and a
  trailing pane for the result card and solution. These are the only High findings
  that block a task on today's 27.1 build.
- **New Game sheet** (F18) needs the same board height cap inside a sheet.
- The **missing banners in Puzzle Analysis** (F14) and the **sign-in keyboard**
  overlap (F21) also affect a normal iPhone, so they are fixed ahead of D08 in their
  own PR (`fix-analysis-banners-signin-keyboard`).
- Confirmation dialogs and menus (F15, F16) get one frame per size class under §5
  rule 5, drawn from state rather than anchored.

**Phase 4 — Mockups.** *Done 2026-11-05 (§8.5).* Build the canvases to the §5 rules, in the order Analysis
(riskiest), Session and detail, Shell and homes, then the rest. Share the link
after each canvas so the direction can be corrected early. Check every frame
against §6, then fill the coverage grid.

### 8.5 Phase 4 progress

**Canvas format.** The session that built the canvases had no claude.ai Artifact
tool, so each canvas is a static HTML page in `design/iphone-duo/` instead of a
Design artifact. The §5.1 conventions hold: one component set (`kit.js`,
`kit.css`), one table of states and drawn cells per canvas, frames at 1:1 points
from §8.1, device chrome with the camera, fold line and shaded division, chips
for size class, bar edge, container and board size, a dark mode toggle and a
coverage grid tab. `render.mjs` renders any frame or state row to PNG with
Playwright (`PLAYWRIGHT_FROM=<repo>/node_modules/`), and `sheet.mjs` joins PNGs
into a contact sheet. The pages can be pasted into a Design artifact later.

**Analysis canvas (S15, S10), 2026-11-05.** 28 states × 8 columns = 224 cells: 92
drawn, 132 marked with the frame they equal, none blank; plus 8 system-variant
frames, 6 storyboard frames, S15a on both Split View sides and an FT alternative.
Direction drawn, for review:
- **Layout rule:** wider than tall → board pane + column; taller than wide →
  stacked; an active division puts the split on the fold. `AnyLayout` switches, so
  `GameViewModel` survives.
- **No custom capsule.** Flip Board and Engine Lines are top toolbar items, and
  Previous / Next Move are a `.bottomBar` group. The system puts them in the side
  bar (O, SV, IL, FB) or the navigation and bottom bars (IP, FT, iPad), so nothing
  custom reads `toolbarVerticalEdge`, and the toast collision (F24) goes away.
- **Overflow:** the game ⋯ menu becomes `ToolbarOverflowMenu` (F16).
- **Boards:** O 328 pt (6 move rows), SV 316 pt, IL 504 pt (from 293, F6), FB
  392 pt on the left page (F3), IP 512 pt (capped so the column keeps 240 pt), FT
  272 pt above the division (F4), iPad 704 pt.
- **Short columns** (O, SV, IP): engine lines replace the move list, alternatives
  are one scrolling row of 44 pt chips, the comment shows one line (F7, F8).
- Promotion is a row of 56 pt buttons in the column (F12); confirmation dialogs
  anchor to the row or toolbar item that asked (F15); Save as Game is a fitted sheet
  (F17, F29); Puzzle analysis shows the offline pill (F14).

**Session and detail canvas (S09, S08), 2026-11-05.** 24 states × 8 columns = 192
cells: 81 drawn, 111 marked with the frame they equal, none blank; plus 8
system-variant frames, the unfold-mid-session storyboard and S09a on both Split
View sides. The layout rule moved into `kit.js` (`boardGeom`) so every board
screen shares it; without the eval bar the boards are O 350 pt, SV 336 pt, IL
504 pt, FB 416 pt, IP 512 pt, FT 272 pt, iPad 704 pt, the same as Puzzle analysis
in each pose. Direction drawn:
- **The board always fits without scrolling** (F1, F2, F11): pinned, with only
  the column scrolling. Puzzle detail's info list scrolls under it on compact.
- **Skip becomes a `.bottomBar` toolbar item** (side bar on O, SV, IL, FB; a
  titled capsule on IP, FT, iPad), replacing the overlay that collided with the
  toast and banner (F24, F25).
- **Result card (F5):** in the column beside the board on two panes (≤ 560 pt);
  below the board on IP and FT; on compact it still rises from the bottom but is
  sized to its content (a short result covers 22 pt of the board), capping at 62 %
  and scrolling for long results.
- **Pickers** sit under the board or atop the column, never over the board (F12).
- **Session complete (F27):** ≤ 480 pt; split across pages on FB and across the
  division on FT.
- **Puzzle detail:** Copy FEN / Delete Puzzle move to `ToolbarOverflowMenu` (F16);
  solution chips 44 pt; the delete confirmation anchors to the overflow item (F15).

**Shell and homes canvas (S01–S04, S11, S17), 2026-11-05.** 47 states × 8 columns
= 376 cells: 121 drawn, 255 marked with the frame they equal, none blank; plus 20
system-variant frames (all five primary states on O and IL), S04a on both Split
View sides and one `.sidebarAdaptable` comparison. S17 on the S15 and S09 hosts is
added to those canvases (5 states each, drawn on O and IL). Direction drawn:
- **Shell (decision 4):** `TabView` + one `NavigationSplitView` per tab, two
  columns. Regular: home list as the sidebar (340 pt on IL, the left page on FB,
  300 pt on IP), selected collection as the detail; a pushed board screen hides
  the sidebar. Three columns would leave the board screens under 300 pt.
  `.sidebarAdaptable` would squeeze the detail to 365 pt for two tabs, so it isn't
  chosen.
- **Avatar (F32)** becomes a titled "Account" toolbar item beside +.
- **Banners (F25, F26), one rule on every canvas:** Offline / Offline · N waiting
  is a pill trailing the title; server errors, dismissible errors and toasts are a
  glass capsule ≤ 480 pt at the bottom of the content, never over a board.
- **Sign in and launch:** centered column ≤ 480 pt; with the keyboard up the
  header collapses to the title so the fields and Sign In stay above it.
- **Account sheet:** opts out of the vertical bar on compact (one item, ✕); the
  reset confirmation anchors to its row inside the sheet (F15).
- FT shows the IP layout for these screens: lists are scrolling content.

**Lists canvas (S06, S07, S12), 2026-11-05.** 33 states × 8 columns = 264 cells:
87 drawn, 177 marked with the frame they equal, none blank; plus 12 system-variant
frames, the "enter Split View in edit mode" storyboard and S12f on both Split View
sides. Direction drawn:
- These screens are the **detail column** on regular width (decision 12): 526 pt
  on IL, the right page on FB, 368 pt on IP; content ≤ 672 pt on iPad. The sidebar
  keeps the home list with the collection selected.
- **⋯ menus → `ToolbarOverflowMenu`** (F16); + (Add Games) keeps its own menu.
- **Search scopes (F23):** `.searchScopes(…, activation: .onSearchPresentation)`
  shows the scope bar as soon as search is active.
- **Edit mode (F30):** Select All / Deselect All becomes a titled toolbar item
  beside Done; the bulk items stay a `.bottomBar` group (side bar on O, SV, IL,
  FB; a capsule on IP and iPad, titled where the column is ≥ 440 pt).
- Confirmations anchor to the overflow item, the Delete bulk item or the row
  (F15); the destination sheet is fitted; the share sheet is a popover from Export
  on regular width.

**Sheets canvas (S05, S13, S14, S16), 2026-11-05.** 35 states × 8 columns = 280
cells: 95 drawn, 185 marked with the frame they equal, none blank; plus 16
system-variant frames and the "fold with a sheet and keyboard" storyboard.
Direction drawn:
- **System placement as measured in Phase 1:** side ✕ / ✓ on O and SV (below the
  status zone), centered 653 pt on IL and IP, the left page on FB, below the
  division on FT. Each keyboard frame records how much of the form stays visible.
- **New Game (F18):** the preview board is capped. On IL and iPad (sheets
  ≥ 600 pt, regular width inside) it sits beside the form; everywhere else (O,
  SV, IP, FT, and FB's 440 pt sheet) it is stacked and capped at 40 % of the
  visible sheet, so the FEN field and its error stay visible. With the keyboard
  up on O that leaves a 96 pt preview.
- **Offline (F19):** the "needs a connection" note moves to the top of the form.
- **Comment editor (F20):** solid background; F29 stays accepted.

**Phase 4 totals.** Five canvases, 167 states plus S17 on three hosts (175 rows):
1,416 cells, 496 drawn and 920 marked with the frame they equal, none blank;
581 frames in all including system variants, storyboards and comparisons (the §5
estimate was ~600). All five §5 rule 7 storyboards are drawn. Every canvas has a
coverage grid tab and a §6 check tab. Next: Phase 5 review.

Open for Phase 5:
- ~~Q1 — FT board~~ settled as decision 10.
- ~~Q2 — IL board~~ settled as decision 11.

**Phase 5 — Review.** *Done 2026-11-06 (§8.6).* Settle §10 with the user, update
the mockups, and record the decisions here (like §7 of the refresh plan).

### 8.6 Phase 5 results (2026-11-06)

The user reviewed the five canvases (rendered contact sheets of S15a, S15c, S09a,
S09i, S08a, S04a, S12f and S14c in every pose) and approved every recommendation,
asking for the approaches Apple documents and follows in its own design guidance.
The design is for the first release and will change after it ships. Recorded as
decisions 13–22 (§10). Each names the API it rests on, so the build prompts (Phase 6)
can cite it.

Canvas changes:
- **Decision 16** (open tall, IP and FT): `shellGeom` gives the detail the full 669 pt
  with an overlay sidebar (320 pt). `shell.js` draws S04a·IP and S11a·IP twice:
  detail only, and with the sidebar shown. The empty states (S04d, S11b) show the
  sidebar, since nothing is selected. The Lists canvas detail on IP is now 669 pt
  (bulk-bar items titled), with the sidebar button before Back. Coverage counts are
  unchanged apart from the two extra frames. FT follows IP as before.
- The "for review" headings on all five canvases now read "approved in Phase 5".
- Decisions 13–15, 17–22 were already drawn as approved; no frame changed.

Carried into Phase 6:
- D02 checks on the device which overlay `NavigationSplitViewStyle.automatic` gives
  at 669 pt (decision 16) before choosing a style explicitly.
- `ToolbarOverflowMenu` and `toolbarVerticalBehavior` are iOS 27.1 APIs. Every use
  is gated with `if #available(iOS 27.1, *)`, with today's `Menu` (ellipsis) and
  default toolbar behavior as the fallback on iOS 26.1 to 27.0 (§8 Phase 0).
- Decisions 13, 14, 15, 17, 18, 19 and 22 also change a normal iPhone. D01's regression
  pass and D09's screenshot tests cover an iPhone 17 alongside the Duo poses.

**Phase 6 — Slices.** *Done 2026-11-07 (§9).* Turn the approved mockups into
build prompts (§9) in the existing format (`scripts/run-ios-*-prompts.sh`).

### 8.7 Build log

Each slice adds a line or two here: what it settled on the runner or the device
(e.g. the split view style D02 chose at 669 pt, the iPhone 17 runtime D01 found),
and anything deferred to a later slice or a follow-up PR.

- **D01:** `ios-ci` runs on `xcode-27` with Xcode 27.1 as a two-job matrix, `iphone`
  (`MOTIF_SIM="iPhone 17"`, `MOTIF_RUNTIME=26`: an iOS 26.x runtime when the image has
  one, else 27.1; the "Build and test" log names the runtime used) and `IL` (a fresh
  "Motif Duo Capture" posed by the new `ios-duo-capture.sh pose`). TestFlight builds on
  27.1 by default; the `xcode_26` input falls back to `macos-26`. `SystemCompat.swift`
  holds `motifToolbarVerticalBehaviorDisabled()`, unused so far. The first run found no
  iOS 26.x runtime on the image: the iPhone 17 ran on iOS 27.2. On that runtime, menu items
  inside a `Section` (Copy PGN, Export PGN…, Save as Game…) lose their identifiers, so UI
  tests find them by title too (`FlowTestCase.button(_:title:)`), and a text field tap can
  leave no keyboard focus, so `type(_:into:)` taps again until it has it.
  `ios-simulator.sh` reads runtime versions from `simctl list runtimes`, since the Duo's
  device wasn't found by its runtime identifier alone.

## 9. Implementation slices

Phase 6 (2026-11-07) turned the approved canvases into one build prompt per slice,
in the format of the UI refresh (`Motif - iOS UI Refresh Plan.md` §8) and run by
the same driver, in batch mode (§9.1): every slice is a commit on one branch, and
`ios-ci` runs once, after D11.

| Slice | Scope | Main files | Findings, decisions |
|---|---|---|---|
| **D01** Toolchain | `ios-ci` and TestFlight on Xcode 27.1 (`xcode-27`); a PR check on an iPhone 17 and on the Duo simulator opened wide (IL); the gated-API file | `.github/workflows/`, `scripts/ios-verify.sh`, `UI/Shared/SystemCompat.swift` | §8 Phase 0, decisions 2, 3 |
| **D02** Shell | One `NavigationSplitView` per tab with a shared navigation model; titled toolbar items; `ToolbarOverflowMenu`; dialogs from state | `RootView`, `AppState`, `PuzzlesHomeView`, `GamesHomeView`, every ⋯ menu | F15, F16, F31, F32; decisions 4, 12, 16 |
| **D03** Puzzles columns | Collection and puzzle list as the detail column; readable width; scopes on presentation | `CollectionView`, `PuzzleListView`, `PuzzlesHomeView` | F13, F22, F23; decision 19 |
| **D04** Games columns | Game collection as the detail column; edit mode toolbar; titled bulk bar | `GameCollectionView`, `GamesHomeView` | F13, F22, F30; decision 20 |
| **D05** Board layout rule, Analysis | `BoardLayout` (the `boardGeom` rule in Swift) and the Analysis view on it; system toolbar controls; short columns; promotion row | new `UI/Board/BoardLayout.swift`, `GameView`, `MoveListView`, `EngineLinesView` | F6–F9, F12, F24; decisions 5, 11, 13, 17 |
| **D06** Puzzle detail and session | Both on `BoardLayout`: pinned board, Skip in the bottom bar, the result card in the column, pickers in the layout, session complete | `PuzzleDetailView`, `SessionView`, `PuzzleSolveView`, `MissingPieceSolveView`, `ResultCard`, `PiecePicker` | F1, F2, F5, F10–F12, F25, F27; decisions 14, 15, 17, 18 |
| **D07** Folded poses | The division (`ReservedRegion`) in `BoardLayout`: FB pages, FT halves, the Split View inner edge | `BoardLayout`, `SystemCompat` | F3, F4, F33; decision 10 |
| **D08** Sheets, banners, sign-in | One banner rule; sheets per the Sheets canvas; New Game preview cap; Account sheet opt-out; sign-in and loading column | `Banners.swift`, `Toast.swift`, `NewGameView`, `SaveAsGameSheet`, `CommentSheet`, `ImportView`, `ImportPGNView`, `AccountView`, `SignInView`, `RootView` | F17–F20, F22, F26, F29; decisions 21, 22 |
| **D09** Screenshot tests | `DuoCaptureTests` → one screenshot per drawn cell × pose, on the Duo and an iPhone 17, paired with the rendered mockup frame | `MotifUITests/DuoCaptureTests.swift`, `CaptureFixture`, `ios-duo-capture.yml`, `scripts/` | §8.4 capture issues |
| **D10** Polish | AX5, dark mode, Reduce Transparency / Increase Contrast, VoiceOver order across panes, contrast | any view | F35; §6.10–6.14 |
| **D11** iPad | Device family, iPad orientations, iPad simulator in CI, spot checks incl. Stage Manager sizes | `project.pbxproj`, `Info.plist`, workflows | decision 6 |

**Order.** D01 first: until the SDK moves, the app runs in compatibility mode and
nothing below can be seen. D02 before D03 and D04 (they fill its detail column).
D05 before D06 and D07 (they use its `BoardLayout`). D08 needs only D01. D09 after
D02–D08, then D10 and D11. The driver runs them in this order.

**What the final run checks.** From D01, `ios-ci` runs `MotifTests` and
`MotifUITests` twice: on an iPhone 17 and on the iPhone Duo simulator set to IL with
`duoctl` (as in `ios-duo-capture.yml`). UI tests that only hold in one pose read
`MOTIF_POSE` (`iphone`, `IL`) and skip elsewhere. A slice that changes layout adds
UI tests that assert frames, not pixels: board size, the board staying clear of the
division, a column's width, an item being in the toolbar. Other poses are checked
by D09's capture run, which the user starts by hand (`ios-duo-capture.yml`) once
the batch has merged.

### 9.1 Running the slices

**One fresh Claude session per slice**, in order, **all on one branch with no CI
between them** (user, 2026-11-09). Waiting for the macOS runner after every slice
cost more than it caught, so CI runs once at the end and one fix loop clears every
error.

- **Unattended:** from a clean, dedicated checkout, run
  `scripts/run-ios-duo-prompts.sh` (all slices) or `scripts/run-ios-duo-prompts.sh
  D05` (resume at D05, on the existing branch). Each session commits one slice on
  `ios-duo/all`, starting from the branch's tip; nothing is pushed. After D11 the
  driver pushes, opens one PR, runs `ios-ci` and sends each failing log to a fresh
  fix session (up to 10 rounds, `MAX_FIX_ATTEMPTS`), then merges and checks
  TestFlight once (`SKIP_TESTFLIGHT=1` skips that wait).
- **Since no slice is compiled before the end**, each session checks the APIs it
  calls against the code and Apple's docs, updates the tests its change affects,
  and fixes anything an earlier slice obviously broke in the code it touches. The
  fix sessions read the slices' prompts for scope and clear every error in the
  log, not only the first. A fix never weakens or deletes a test to get past it.
- **D01 started in the old per-slice flow** (PR #53, `ios-duo/D01`, two CI
  failures). Its commits are the base of `ios-duo/all`, and its remaining failures
  go to the final fix loop; #53 is closed.
- **Per-slice flow** (a PR and CI per slice) is still there:
  `BATCH_BRANCH= scripts/run-ios-duo-prompts.sh`.
- **By hand:** open a new session in the repo on `ios-duo/all`, paste the slice's
  **Run** line, commit, then start the next slice in a new session.
- **On the device:** only the final merge uploads a TestFlight build, so the
  slices' **Device** checks happen together after it. Anything they turn up
  becomes a follow-up PR.

There is no Mac-mode variant: the Duo simulator and the 27.1 SDK exist only on
the `xcode-27` runner.

### 9.2 Shared rules (inlined into every slice)

> 1. **UI only.** Do not change `Model/`, `Data/`, `Engine/` or the behaviour
>    `src/` defines. View models may change shape; the rules they enforce may not.
> 2. **The approved canvases are the spec**, with §10 decisions 4–22 and §8.5–8.6.
>    They are static HTML in `design/iphone-duo/` (`README.md` there): read the
>    canvas file's state table and `kit.js` (`CFG`, `boardGeom`, `shellGeom`) for
>    sizes, and render the frames the slice names to PNG and look at them
>    (`npm ci` once, then `PLAYWRIGHT_FROM=$PWD/node_modules/ node
>    design/iphone-duo/render.mjs design/iphone-duo/<canvas>.html /tmp/duo
>    "<tab>:#<cell>"`; `npx playwright install chromium` if it asks). Where a
>    frame and this text disagree, the decision in §10 wins; say so in the PR.
> 3. **Lay out by container size and size class**, never by idiom, orientation,
>    `UIScreen` or a pose (§6.2–6.3). One view tree per screen: switch layouts with
>    `AnyLayout` or modifiers so `@State` (sessions, drafts, selection, unsaved
>    moves) survives a fold (§6.15). No new `GeometryReader` where a container
>    size read (`onGeometryChange`, `containerRelativeFrame`) does the job.
> 4. **iOS 27.1 APIs are gated.** The deployment target stays 26.1. Every use of
>    `ToolbarOverflowMenu`, `toolbarVerticalBehavior`, `toolbarVerticalEdge`,
>    `ReservedRegion` / `reservedRegions` and `ArrangementView` goes through a
>    wrapper in `UI/Shared/SystemCompat.swift` with `if #available(iOS 27.1, *)`
>    and today's behaviour as the fallback. Check each API against Apple's
>    documentation (developer.apple.com) before writing it; these APIs are newer
>    than most training data, so don't guess a signature. Keeping them in one file
>    keeps a compile fix in one place.
> 5. **System components first** (§6.1, §6.5): `NavigationSplitView`, `.toolbar`
>    with `ToolbarItem` / `ToolbarItemGroup`, `Button(_:systemImage:)` so every
>    item has a title and a symbol, `.searchable`, `confirmationDialog` /
>    `alert` driven from state, `.sheet` with `SheetToolbar`. No custom capsule,
>    overlay or bar where a system piece exists.
> 6. **Keep accessibility identifiers** the UI tests use, on whatever control now
>    does that job. Items in the vertical side bar lose their identifier (§8.3), so
>    UI tests find toolbar items by title there, as `DuoCaptureTests` does. Update
>    `MotifUITests` in the same slice for anything you move.
> 7. **Never show tags, comments or motif while solving.**
> 8. **Synchronized folders:** new files under `Motif/`, `MotifTests/`,
>    `MotifUITests/` need no `project.pbxproj` edit.
> 9. **No Mac, and no CI until the end.** CI is the only compiler, and it runs
>    once after D11 (§9.1). A slice is done when its "Done when" is written (the
>    tests it names exist and should pass) and committed, with nothing from a
>    later slice; "CI green" in a slice means green in that final run. Record
>    anything the slice settles or defers in §8.7 of this plan, in one or two lines.

### D01 — Toolchain on Xcode 27.1

**Run:**
> In this repo, read `Motif - iOS iPhone Duo Plan.md` §2, §8 (Phase 0, §8.1, §8.2,
> §8.6) and §9 → **D01**. Move `ios-ci` and the TestFlight build to Xcode 27.1 on
> `xcode-27`, run the tests on an iPhone 17 and on the iPhone Duo simulator opened
> wide, and add the gated-API file. Commit; `ios-ci` runs after D11.

**Build:**
- `ios-ci.yml`: `runs-on: xcode-27`, Xcode pinned to `27.1` (as
  `ios-duo-capture.yml` does). A matrix of two destinations: `iphone` (an iPhone
  17; on an iOS 26.x simulator runtime if the image has one, so the 26.1 fallbacks
  run, otherwise on 27.1, and say which in §8.7) and `IL` (the iPhone Duo, set
  open + landscape with `duoctl` before the tests, as `scripts/ios-duo-capture.sh`
  does). `fail-fast: false`; the xcresult upload names the destination. The
  driver waits on the workflow run, so a red destination fails the run. Keep the
  `web` job and the `paths` filter (every slice touches `iOS/**`).
- `scripts/ios-verify.sh`: an optional `MOTIF_SIM` (device name or UDID) and
  `MOTIF_POSE`, passed to the tests as a test-plan environment variable; the
  default stays "first available iPhone" so the Mac flow still works.
- `ios-testflight.yml`: Xcode 27.1 on `xcode-27` becomes the default for pushes
  to `main`; the `xcode_27` input becomes `xcode_26` (fallback to `macos-26`).
  Build numbers stay in one sequence.
- `UI/Shared/SystemCompat.swift`: the home for gated wrappers (§9.2 rule 4),
  empty but for a short doc comment and one wrapper the next slices need first:
  `View.motifToolbarVerticalBehaviorDisabled()` or similar, checked against the
  docs. Nothing in the app uses it yet.
- `Info.plist`: no change. Decision 2 (outer display portrait only) is today's
  value, and Phase 1 showed Split View needs none (decision 3). iPad keys wait
  for D11.
- Fix only what the 27.1 SDK breaks (deprecations that fail the build, test
  queries that no longer match on the Duo). Tests that can't hold on IL until a
  later slice (e.g. a tap on a toolbar item by identifier) switch to the title.

**Out of scope:** any layout change. **Device:** the TestFlight build from this
merge runs edge to edge on the Duo, closed and open.
**Done when:** `ios-ci` green on both destinations at Xcode 27.1; the merge to
`main` uploads a 27.1 TestFlight build.

### D02 — Shell: split view per tab, toolbars, overflow, dialogs

**Run:**
> In this repo, read `Motif - iOS iPhone Duo Plan.md` §1, §6, §7 "App shell",
> §8.5 "Shell and homes", §8.6, §10 (decisions 4, 7, 12, 13, 16) and §9 → **D02**.
> Put each tab in one `NavigationSplitView` with a shared navigation model, give
> every toolbar item a title, move custom ⋯ actions into `ToolbarOverflowMenu`, and
> drive every confirmation dialog from state. Commit; `ios-ci` runs after D11.

**Mockups:** `shell.html` homes tab: S04a, S04d, S11a, S11b on O, IL, IP (both
S04a·IP frames), FB; S04g–j and S11d–h (overlays, O and IL); the
`.sidebarAdaptable` comparison is not built.
**Build:**
- **Navigation model.** `AppState` keeps one selection per tab
  (`puzzlesCollection`, `gamesCollection`: the collection shown in the detail
  column) plus `puzzlesPath` / `gamesPath` for what is pushed on top of it, and
  `columnVisibility` per tab. Selecting a collection in the sidebar sets the
  selection and clears the path. Existing callers and launch routes that set a
  full path (`[.collection(id), .puzzles(id), .puzzle(…)]`) keep working through
  one function that splits it into selection + path; add a `MotifTests` case for it.
- **Shell.** `TabView` (two tabs, unchanged) → in each tab
  `NavigationSplitView(columnVisibility:)`: sidebar = the home list (selection
  bound to the tab's collection), detail = `NavigationStack(path:)` rooted at the
  selected collection screen, or the home's empty state when nothing is selected.
  Compact width collapses to one stack by itself; check that Back from the
  collection returns to the home list and clears the selection. A pushed board
  screen (puzzle detail, Analysis view) sets `.detailOnly`; popping restores the
  previous visibility. Start from `.navigationSplitViewStyle(.automatic)`
  (decision 16); if IP (669 pt) shows two columns rather than the overlay sidebar,
  switch to `.prominentDetail` below a width threshold and record it in §8.7.
  Sidebar width per `shellGeom` (340 pt on IL) via
  `.navigationSplitViewColumnWidth`. `libraryBanners()` stays on every column
  root and pushed screen.
- **Toolbars (F31, F32, decision 13 groundwork).** Tabs keep their titled `Tab`;
  check the vertical tab bar's labels against the frames and record what the
  system shows. The avatar becomes `Button("Account", systemImage:
  "person.crop.circle")` in the toolbar beside + (identifier kept). Every toolbar
  item in the app is a `Button(_:systemImage:)` or a `Menu` with a titled label;
  give status-bearing items a higher `ToolbarItemVisibilityPriority` where the
  docs offer it.
- **Overflow (F16).** One wrapper in `SystemCompat.swift`: on 27.1 the custom
  actions go in `ToolbarOverflowMenu`; before 27.1, today's `Menu` with the
  ellipsis. Use it for the Analysis game menu, puzzle detail (Copy FEN, Delete
  Puzzle), collection and game collection ⋯ menus. + (Add Games) keeps its own
  `Menu` with a plus symbol. Keep `game-actions` and the other identifiers on the
  fallback; on 27.1 tests find the items by title.
- **Dialogs (F15).** Every `confirmationDialog` presented from a menu item or
  overflow item is driven by a state flag set by the item and attached to the
  screen (or to the row for row actions), never inside the menu, so it doesn't
  anchor to a control that moved. The Account reset dialog anchors to its row
  inside the sheet.
- **Continuity.** A `MotifTests` case on the navigation model: with a collection
  selected and a puzzle pushed, collapsing to one stack and expanding again keeps
  both. A UI test on IL opens a collection and a puzzle through the sidebar. The
  fold itself is a device check.

**Out of scope:** detail column contents and widths (D03, D04), board layouts (D05),
banners (D08).
**Device:** the overlay `.automatic` gives on IP (decision 16); fold/unfold with a
collection and a puzzle open keeps both; Split View halves show the compact stack.
**Done when:** on IL the homes show sidebar + detail and a pushed board hides the
sidebar; on the iPhone 17 navigation is unchanged; every ⋯ is the overflow wrapper;
UI tests updated; CI green on both destinations.

### D03 — Puzzles columns

**Run:**
> In this repo, read `Motif - iOS iPhone Duo Plan.md` §6.7, §7 "Lists", §8.5
> "Lists" and "Shell and homes", §10 (decisions 12, 19) and §9 → **D03**. Fit
> Puzzles home, the collection and the puzzle list to the split view columns at
> readable width, and show search scopes on presentation. Commit; `ios-ci` runs after D11.

**Mockups:** `shell.html` homes tab S04a–f on O, IL, IP; `lists.html` S06a–g, S07a–i
on O, IL, IP, FB (detail 526 pt on IL, the right page on FB, 669 pt on IP).
**Build:**
- Sidebar rows for Puzzles home (Practice section, collections with progress rings)
  as drawn: selection highlight on regular width, push on compact. Practice actions
  (Solve All, Review) still start sessions and don't change the selection.
- Detail column: collection stats card and session card, puzzle list rows and
  thumbnails at the column's width; on iPad-sized columns, content capped at
  ~672 pt (§6.7) with `.frame(maxWidth:)` centred, lists left to the system.
- Empty states (F13): `ContentUnavailableView` descriptions wrap within the
  readable width.
- Search scopes (F23, decision 19): `.searchScopes($scope, activation:
  .onSearchPresentation)` (check the parameter name in the docs; gate if it is
  27.1-only). S07c becomes reachable: activate search, pick Flagged, no text.
- Keep `solve-ordered`, `resume-session`, `browse-puzzles`, `puzzle-<id>`,
  `collection-<id>`, `solve-all`, `import-puzzles`.

**Out of scope:** puzzle detail's own layout (D06); the import sheet (D08).
**Done when:** a UI test picks a scope with an empty query and sees the filtered
list; on IL the puzzle list fills the detail column beside the sidebar; CI green.

### D04 — Games columns

**Run:**
> In this repo, read `Motif - iOS iPhone Duo Plan.md` §6.5, §7 "Lists", §8.5
> "Lists" and "Shell and homes", §10 (decisions 12, 20) and §9 → **D04**. Fit
> Games home and the game collection to the split view columns, and move Select
> All / Deselect All into the toolbar with titled bulk actions. Commit; `ios-ci` runs after D11.

**Mockups:** `shell.html` homes tab S11a–i; `lists.html` S12a–q on O, IL, IP, FB
and the "enter Split View in edit mode" storyboard.
**Build:**
- Games home as the sidebar, the game collection as the detail column, as D03 did
  for Puzzles (readable width, empty states F13).
- Edit mode (F30, decision 20): `Button("Select All", systemImage:
  "checkmark.circle")` / `Button("Deselect All", systemImage: "circle")` as a
  toolbar item beside Done. The bulk actions stay one
  `ToolbarItemGroup(placement: .bottomBar)` of titled `Button(_:systemImage:)`s
  (Move, Copy, Export, Delete), so the system puts them in the side bar or the
  bottom capsule.
- Edit mode and the selection survive a size change (they live in
  `GameCollectionModel` / `@State` on the same view): a model test.
- The destination sheet stays fitted; the share sheet presents from Export.
- Keep `new-game-collection`, `game-collection-name`, `game-collection-<id>`,
  `game-search`, `add-games`, `game-row-<id>`.

**Out of scope:** the Analysis view (D05); Import PGN and New Game (D08).
**Done when:** bulk move/copy/export/delete still work from the toolbar items; UI
tests find them by title on IL; CI green.

### D05 — Board layout rule and the Analysis view

**Run:**
> In this repo, read `Motif - iOS iPhone Duo Plan.md` §3, §6.4–6.6, §7 "Board
> layout rule" and "Analysis view", §8.1, §8.5 "Analysis canvas", §10 (decisions
> 5, 10, 11, 13, 17) and §9 → **D05**. Port the canvas board rule to a shared
> `BoardLayout`, rebuild the Analysis view on it with system toolbar controls, and
> put promotion in the layout. Commit; `ios-ci` runs after D11.

**Mockups:** `analysis.html` s15 tab: S15a, S15b, S15c, S15e, S15f, S15g, S15k, S15v
on O, SV, IL, IP, and S15a on the 457 pt case-gap check; s10 tab S10a–f on O and IL.
FB and FT frames are D07's.
**Build:**
- `UI/Board/BoardLayout.swift`: a pure function from container size (inside the
  safe area), size class, eval bar on/off and a minimum column height to a mode
  (`stack` or `panes`), a board size snapped to 8 pt, and the column frame. It is
  `boardGeom` in `design/iphone-duo/kit.js` without the device table: wider than
  tall → panes, board capped by height (504 pt on IL per decision 11, leaving the
  column ≥ 263 pt); taller than wide → stacked, board by width but leaving the
  column 240 pt (IP 512 pt); compact → stacked at full width minus margins (O 328 /
  350 pt). `MotifTests` cases for each §3 size (O, O case gap, SV, IL, IP, PP flat
  and bent, iPad portrait and landscape), with and without the eval bar, against
  the canvas numbers. A `division` input is accepted and ignored until D07.
- `GameView` on it: one `AnyLayout` (`HStackLayout` / `VStackLayout`) switched by
  the mode, so `GameViewModel`, the analyzer and the sheets survive.
- **Controls (decision 13, F24).** Remove the `.safeAreaBar` capsule. Flip Board
  and Engine Lines are top `ToolbarItem`s; Previous / Next Move a
  `ToolbarItemGroup(placement: .bottomBar)`; all `Button(_:systemImage:)`. The
  game menu is D02's overflow wrapper. Keyboard arrows stay.
- **Short columns (F7, F8).** Where the column is short (O, SV, IP), engine lines
  replace the move list when shown; alternatives are one horizontally scrolling
  row of 44 pt chips under the board, never over it; the comment card shows one
  line and opens the sheet. Move rows and chips reach 44 pt where the canvas
  draws them so (F9 records the rest).
- **Promotion (decision 17, F12).** A row of four 56 pt `Button`s (titled for
  VoiceOver) under the board when stacked, at the top of the column on two panes.
  `BoardView`'s picker overlay goes for the Analysis view; the session keeps it
  until D06.
- Puzzle analysis (S10) uses the same view; its offline pill already shows (#48).
- Keep `eval-bar`, `game-actions`, `game-back`, `square-*`, the move-row and
  engine-line identifiers.

**Out of scope:** the division (D07); puzzle detail and session (D06).
**Device:** IL board 504 pt with the column beside it; O unchanged at 328 pt.
**Done when:** `BoardLayout` tests pass; a UI test on IL finds the board at 504 pt
(± 1) with Previous / Next in the toolbar; the iPhone 17 Analysis view keeps every
feature; CI green.

### D06 — Puzzle detail and session

**Run:**
> In this repo, read `Motif - iOS iPhone Duo Plan.md` §7 "Puzzle detail and
> session", §8.5 "Session and detail canvas", §10 (decisions 14, 15, 17, 18) and §9
> → **D06**. Put puzzle detail and the session on `BoardLayout` with the board
> pinned, Skip in the bottom bar, the result card in the column and the pickers in
> the layout. Commit; `ios-ci` runs after D11.

**Mockups:** `session.html` s09 tab: S09a, S09b, S09e, S09g, S09i, S09k, S09l, S09m
on O, SV, IL, IP and the unfold-mid-session storyboard; s08 tab S08a–i on O, IL, IP.
**Build:**
- **Pinned board (decision 18, F1, F2, F11).** No `ScrollView` around the board in
  `SessionView` or `PuzzleDetailView`. The board sits outside the puzzle detail
  `List`, which scrolls under it in the column or below it. Boards without the
  eval bar: O 350, SV 336, IL 504, IP 512 pt. 16 pt margins on compact (F10).
- **Skip (decision 14, F24, F25).** `ToolbarItem(placement: .bottomBar)` with
  `Button("Skip", systemImage: "forward.fill")`, replacing the overlay; keep
  `session-skip`.
- **Result card (decision 15, F5).** On two panes it is the column's content
  (≤ 560 pt). Stacked with room (IP, FT): below the board. Compact: it still rises
  from the bottom but is sized to its content (`ViewThatFits`), capped at 62 % of
  the container height and scrolling past that (S09l).
- **Pickers (decision 17).** Promotion and the missing-piece picker are rows of
  56 pt buttons under the board or at the top of the column, using D05's row.
- **Session complete (F27).** Content ≤ 480 pt wide, centred.
- Puzzle detail: solution chips 44 pt; the replay controls follow the Analysis
  bottom bar group; Copy FEN / Delete are already in overflow (D02).
- The `fullScreenCover` stays. A fold mid-session keeps `SolveModel`: one view
  tree, `AnyLayout` only.
- Keep `session-stop`, `session-skip`, `result-verdict`, `result-continue`,
  `puzzle-comment`, `puzzle-tags`, `choose-*`, `picker-cancel`, `edit-puzzle-comment`;
  `SolveModel` timing and the drag behaviour from PR #22.

**Out of scope:** the division (D07).
**Device:** a session solved start to finish on O and IL; unfold mid-puzzle.
**Done when:** every solve UI test passes unchanged in intent on both
destinations; on IL the board is 504 pt and the result card doesn't overlap it (a
frame assertion); CI green.

### D07 — Folded poses and the division

**Run:**
> In this repo, read `Motif - iOS iPhone Duo Plan.md` §1 (reserved regions), §3,
> §6.4 and §6.16, §8.1, §8.5, §10 (decisions 8, 10) and §9 → **D07**. Teach
> `BoardLayout` the fold division so boards never cross it on FB, FT or the Split
> View inner edge. Commit; `ios-ci` runs after D11.

**Mockups:** `analysis.html` S15a, S15c, S15k, S10a on FB, FT, SVL, SVR and the
"bend open to book" storyboard; `session.html` S09a, S09e, S09g, S09i, S09m, S08a on
FB, FT, SVL.
**Build:**
- A `SystemCompat` wrapper that reads the active division's frame
  (`reservedRegions(kind: .division)` / `ReservedRegion`, per the docs) into the
  layout's coordinate space, nil before 27.1 or when the region is inactive. The
  frames already include the region's margins (§6.16).
- `BoardLayout` with a division: vertical (FB) → `pages`: board on the leading
  page, snapped to 8 pt (Analysis 392 pt with the eval bar, sessions 416 pt), the
  column on the trailing page; horizontal (FT) → `halves`: board above the
  division (272 pt, decision 10), controls and column below. The thin Split View
  strip (13.5 pt, F33) is an inset on that edge, not a split. Tests for each.
- Analysis, puzzle detail, session and session complete use it; pickers and Skip
  stay off the division. `onHingeChange` is not used for layout.
- Layout changes on bend animate with the system; no custom transition.

**Out of scope:** sheets on the fold (system placement, D08 checks).
**Device:** FB and FT on S15a, S09a, S08a; bend IL → FB in the Analysis view with
engine lines on.
**Done when:** layout tests for FB, FT, SVL, SVR pass; CI green. (CI's IL is flat,
so the division is inactive there: assert the IL layout is unchanged.)

### D08 — Sheets, banners, sign-in

**Run:**
> In this repo, read `Motif - iOS iPhone Duo Plan.md` §6.8, §7 "Sheets" and "Sign
> in and loading", §8.1 (sheets and keyboard), §8.5 "Sheets canvas" and "Shell
> and homes", §10 (decisions 21, 22) and §9 → **D08**. Apply the one banner rule,
> fit the sheets to the Sheets canvas, cap the New Game preview, and centre sign-in
> and loading. Commit; `ios-ci` runs after D11.

**Mockups:** `sheets.html` S05a, S05d, S05i, S05j, S13a, S13h, S14a–f, S16a, S16d on
O, IL, IP, FB and the "fold with a sheet and keyboard" storyboard; `shell.html`
launch, account and banners tabs (S01, S02, S03, S17 on S04).
**Build:**
- **Banners (decision 22, F25, F26).** `libraryBanners()`: Offline / Offline · N
  waiting is a pill trailing the title (`ToolbarItem` or the navigation subtitle,
  as drawn); server errors, dismissible errors and the toast are one glass capsule
  ≤ 480 pt at the bottom of the content via `.safeAreaInset(edge: .bottom)`, clear
  of bars and never over a board. Keep `offline-banner` and the banner/toast
  identifiers.
- **New Game (decision 21, F18).** One `AnyLayout` by the sheet's own width: ≥ 600
  pt → preview beside the form; narrower → stacked, preview capped at 40 % of the
  visible sheet height, so the FEN field and its error stay visible. The FEN draft
  survives the switch.
- **Offline (F19):** the "needs a connection" note moves to the top of the Import
  Puzzles, Import PGN and New Game forms.
- **Comment sheet (F20):** solid background behind the text editor.
- **Save as Game (F17):** fitted detent (`.presentationSizing(.fitted)` or a
  measured detent), not `.large`.
- **Account sheet:** on compact, opt out of the vertical bar (D01's wrapper) so ✕
  stays in its navigation bar.
- **Sign in and loading (F22):** a centred column ≤ 480 pt on regular width; with
  the keyboard up the header collapses to the title so the fields and Sign In stay
  above it (keep #48's fix). Loading, offline and error states in the same column.
- Sheet placement stays the system's (`presentationPlacement` not used).

**Out of scope:** board screens' own layout.
**Device:** S14e on O (96 pt preview), a sheet with the keyboard up while folding.
**Done when:** a UI test on IL finds the New Game FEN field and board side by side
and the toast clear of the bottom bar; banner tests updated; CI green.

### D09 — Screenshot tests

**Run:**
> In this repo, read `Motif - iOS iPhone Duo Plan.md` §5, §8.2, §8.3, §8.4 "Capture
> issues", §8.5 and §9 → **D09**. Turn `DuoCaptureTests` into the screenshot test
> run for every drawn mockup cell in every simulator pose plus an iPhone 17, paired
> with the rendered mockup frame. Commit; `ios-ci` runs after D11.

**Build:**
- Fix the §8.4 capture issues: the S01b / S01d launch race, S02b on IP, S03j via
  the `notice` fixture, S05k / S12q waiting for content, S09m recording results,
  S07c as redefined.
- New states from Phase 4–5 get routes or fixtures: S04a·IP and S11a·IP with the
  sidebar shown, S15k/S09e promotion row, the Split View cells stay device-only.
- `ios-duo-capture.yml`: drop the iOS 26 SDK build (compatibility mode is history
  after D01); poses O, IL, IP, FB, FT plus `iphone` (iPhone 17). After capture, a
  job renders the matching canvas frame for every captured cell
  (`design/iphone-duo/render.mjs`) and joins each pair with `sheet.mjs` into one
  contact sheet per canvas tab and pose, uploaded as artifacts.
- `unreached.txt` per pose must be empty apart from S12h (a held drag) and the
  device-only cells; the job fails otherwise.
- The PR check stays as D01 left it; this run is manual (`workflow_dispatch`).

**Out of scope:** pixel diffing (the mockups are approximations); fixing layouts
the sheets reveal (each gets a follow-up PR against its slice).
**Done when:** the suite, fixtures and workflow are committed. After the batch
merges, the user starts a full run on `main`; it should be green with every pose's
unreached list as above, and its contact sheets get linked in §8.7.

### D10 — Polish

**Run:**
> In this repo, read `Motif - iOS iPhone Duo Plan.md` §5 rule 6, §6.10–6.14, §8.4
> (F35) and §9 → **D10**. Check every screen at AX5, in dark mode and with Reduce
> Transparency / Increase Contrast, fix VoiceOver order across panes and the fold,
> and fix contrast. Commit; `ios-ci` runs after D11.

**Build:** the system-variant frames on each canvas's `var` tab are the target.
No key label truncated at AX5 on O and IL (lists may wrap; toolbar items may go to
overflow). Glass falls back legibly with Reduce Transparency. VoiceOver order on
two panes and across the fold: board, then moves or solution, then controls
(`accessibilitySortPriority` or container order). Secondary text ≥ 4.5:1 in light
and dark (F35). D09's capture gets AX5 and Reduce Transparency fixtures for the
primary states.
**Done when:** a UI test at AX5 on IL reaches every primary action; CI green.

### D11 — iPad

**Run:**
> In this repo, read `Motif - iOS iPhone Duo Plan.md` §3 (PD), §7 "iPad", §10
> (decision 6) and §9 → **D11**. Make Motif a universal app with the regular-width
> layouts, all four iPad orientations and an iPad simulator in CI. Commit; `ios-ci` runs
> after D11.

**Build:** `TARGETED_DEVICE_FAMILY = "1,2"`; `UISupportedInterfaceOrientations~ipad`
with all four; the iPhone keys unchanged (decision 2). `ios-ci` gains an `ipad`
destination (11″, landscape). `BoardLayout` tests already cover 834 × 1194 and
1194 × 834; add a UI test that the iPad shows sidebar + detail and the Analysis
board fits without scrolling. Stage Manager window sizes fall under the same rule
(compact windows get the O layout). iPad screenshots for the App Store are a
release task, not this slice.
**Out of scope:** iPad-only screens or features; multiple windows (decision 7).
**Done when:** CI green on all three destinations; the TestFlight build installs on
an iPad.

## 10. Decisions

1. **Hardware: available.** The user has an iPhone Duo for TestFlight checks.
2. **Outer display landscape: no.** The outer display stays portrait-only.
3. **Split View: take part.** What it requires of `Info.plist` depends on Phase 1.
4. **Regular-width shell: tab bar + `NavigationSplitView`.** `.sidebarAdaptable`
   is still drawn once for comparison.
5. **Analysis view on the outer display: option A.** The side bar stays, and the
   system layout is kept. The measured 84 pt side bar leaves every outer-display
   board under 352 pt: 328 pt with the eval bar, 350 pt without it and in
   sessions, and 9 pt less with the case-gap setting. All of these are accepted
   exceptions to §6.6 (user, 2026-11-03), on condition that the mockups look
   good. Each frame records its board size.
6. **iPad: in scope.** It is cheap: one slice (D11) after the regular-width work,
   with no iPad-specific screens.
7. **Two Motif windows: not built.** No clear use case, and the split view
   columns already show a list beside its detail.
8. **Standing on its edges: no mockups.** It looked the same as the partly
   folded book pose on the device, so ST is dropped as a configuration (§3).
9. **Pinned video: not captured or drawn for now.** The user doesn't expect to use it
   much (2026-11-04). PP cells read "= IL" until it is revisited.
10. **Tabletop (FT) board: keep the system navigation bar.** The board is 272 pt
    (34 pt squares) above the division, an accepted exception to §6.6 like
    decision 5 (user, 2026-11-05). Hiding the bar to reach 304 pt (S15a·FT alt) is
    not pursued.
11. **Open-wide (IL) Analysis board: 504 pt** (63 pt squares), leaving a 263 pt
    column. 560 pt fits the height but leaves 207 pt, which cuts engine lines to
    about two moves and pushes IL toward the compact "lines replace the move list"
    layout (user, 2026-11-05).
12. **Regular-width split: two columns** (home list | selected collection), not the
    three sketched in §7. A pushed board screen hides the sidebar. A third column
    would leave the puzzle detail board under 300 pt at 867 pt (user, 2026-11-05).

13. **Analysis controls: system toolbar items, no custom capsule** (F24). Flip
    Board and Engine Lines are `ToolbarItem`s at the top, Previous / Next Move a
    `ToolbarItemGroup(placement: .bottomBar)`, each a `Button(_:systemImage:)` so
    it has a title and a symbol. The game ⋯ menu becomes `ToolbarOverflowMenu`
    (F16; iOS 27.1, gated). The `.safeAreaBar` capsule goes. Applies on every
    iPhone (user, 2026-11-06).
14. **Skip: a `.bottomBar` toolbar item** (`Button("Skip", systemImage:
    "forward.fill")`) instead of the overlay (F24, F25). Every iPhone.
15. **Result card on compact width: sized to its content**, capped at 62 % of the
    container height and scrolling past that (S09l). `ResultCard` keeps its
    `ViewThatFits`; the cap comes from the container size the screen already
    reads. On two panes the card sits in the column; stacked with room (IP, FT),
    below the board (F5).
16. **Open tall (IP, FT) homes: detail only, sidebar over it.** The same
    `NavigationSplitView(columnVisibility:)`; with a collection selected the window
    shows the detail with the system sidebar button, and the home list slides over
    it (overlay), as on iPad in portrait. With nothing selected the sidebar shows.
    D02 starts from `.navigationSplitViewStyle(.automatic)` and switches to
    `.prominentDetail` by container width only if the device shows two columns at
    669 pt. Two columns stay on IL, FB and iPad landscape (decision 12). Replaces
    the 300 + 368 pt split drawn in Phase 4.
17. **Promotion and piece pickers: in the layout, not over the board** (F12). A
    row of four 56 pt `Button`s under the board (stacked) or at the top of the
    column (two panes). Every iPhone.
18. **Puzzle detail: the board is pinned** (F1, F11). The board sits outside the
    `List`, which scrolls under it in the column or below it; no `ScrollView`
    around the board in puzzle detail or the session. Every iPhone.
19. **Search scopes on presentation** (F23):
    `.searchScopes($scope, activation: .onSearchPresentation)`, so a scope can be
    picked before typing. Every iPhone.
20. **Edit mode: Select All / Deselect All is a toolbar item** with a title and a
    symbol, beside Done (F30). The bulk actions stay a `.bottomBar` group.
21. **New Game preview: capped.** Sheets at least 600 pt wide (IL, iPad) put the
    board beside the form; narrower ones (O, SV, IP, FT, FB) stack it, capped at
    40 % of the visible sheet, one `AnyLayout` switched by container width so the
    FEN draft survives. With the keyboard up on O that leaves a 96 pt preview,
    accepted for the first release (F18).
22. **Banners: one rule everywhere** (F25, F26). Persistent status (Offline,
    Offline · N waiting) is a pill trailing the title. Transient banners and toasts
    are a capsule at most 480 pt wide at the bottom of the content
    (`.safeAreaInset(edge: .bottom)`), clear of bars and never over a board. Every
    iPhone.

## 11. Done when

- §3 has measured values for every configuration, and §4 has been re-checked
  against the code.
- The Phase 2 screenshot grid and Phase 3 findings table are in this file.
- The canvases cover every cell required by §5, with no blank cell in the
  coverage grid. Each frame passes the §6 checklist (or records an accepted
  exception), and the links are at the top of this file.
- §10 decisions are recorded, and §9 holds a build prompt for every slice.

## 12. Sources

- [Apple — Designing for iPhone Duo (HIG)](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) (read in full 2026-11-03)
- [Apple — iPhone Duo tech talk](https://developer.apple.com/videos/play/tech-talks/111466/)
- [Apple Developer Forums — iPhone Duo group lab summary](https://developer.apple.com/forums/thread/847644)
- [Apple — iPhone Duo Tech Specs](https://support.apple.com/en-us/148588)
- [GitHub runner images — Xcode 27 image contents](https://github.com/actions/runner-images/blob/releases/xcode-27-arm64/20261026/images/macos/xcode-27-arm64-Readme.md)
- [GitHub runner images — `xcode-27` label](https://github.com/actions/runner-images/issues/14404)
- [Figma Forum — 890 × 626 vs 951 × 669](https://forum.figma.com/report-a-problem-6/iphone-duo-open-preset-is-890-626-but-apple-s-kit-and-app-store-connect-point-to-951-669-59341)
- [Blake Crosley — iPhone Duo for developers](https://blakecrosley.com/blog/iphone-duo-for-developers)
- [MacRumors — iPhone Duo roundup](https://www.macrumors.com/roundup/iphone-duo/)
