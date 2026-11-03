# Motif — iOS iPhone Duo Plan

> Investigate every iOS screen on the iPhone Duo (Apple's foldable, shipped
> 2026-10-23 with iOS 27.1) and produce mockups on a canvas for every screen in
> every state, on every display configuration the Duo can put the app in. Every
> design uses standard iOS containers and controls and follows the Human
> Interface Guidelines (§6).
>
> This plan covers **investigation and mockups only**. Implementation slices
> (D01–D10, §9) are sketched so the mockups can be checked against what we
> can build. They get their own build prompts once the mockups are approved.
>
> Prior work this builds on: UI refresh (`Motif - iOS UI Refresh Plan.md`,
> mockups https://claude.ai/artifact/LWDMhxnGuDKZFqkdQ79QCb), Analysis view
> update (https://claude.ai/artifact/3k2Bpr381a9BzaSCfyGgHj), puzzle → analysis
> (https://claude.ai/artifact/RKcf2qk5mBRwyKdTj1MhRN).
>
> Checked against the code at `fd6675b` and Apple's guidance on 2026-11-02.
> Decisions recorded 2026-11-03 (§10). Outer-display Analysis options:
> https://claude.ai/artifact/1jThHMrrJzkPHC77F25JR2

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
  `NavigationSplitView` in it), `presentationPlacement`, `toolbarVerticalEdge`,
  `toolbarVerticalBehavior`, `ToolbarOverflowMenu`.

Where sources conflict, Phase 1 settles it: whether a portrait-locked app takes
part in Split View (the labs say it still gets the size-class changes, while the
tech talk says Split View needs a freely resizable app), and whether
`ArrangementView` needs 27.1 or works from 27.0.

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
| **O** | Closed, portrait | compact × regular | 466 × 678, less the side bar | Vertical on the trailing edge. Height and width are both tight |
| **IL** | Open flat, wide (as opened) | regular × regular | 951 × 669 | Vertical. Fold vertical in the middle, zero width when flat |
| **IP** | Open flat, tall | regular × regular | 669 × 951 | Horizontal. Fold horizontal |
| **SV** | Split View half | **verify** | ~475 × 669 | Controls on the app's outer edge; draw both the leading and trailing sides |
| **PP** | Another app's video pinned on top | regular × shorter (**verify**) | 951 × ~400 (**verify**) | Height changes live; wider than tall |
| **FB** | Partly folded book (IL bent) | regular × regular + division | two ~475 × 669 pages | Controls go to the sides, none on the fold |
| **FT** | Partly folded portrait or tabletop (IP bent) | regular × regular + division | two 669 × ~475 halves | Controls on the stable bottom half; board on top |
| **ST** | Standing on its edges | regular × regular + division | as FB or FT | No Apple guidance. Expected to match FB or FT; confirmed in Phase 1 |
| **PD** | iPad, 11″ portrait and landscape | regular × regular | 834 × 1194 and 1194 × 834 | Expected to match IP and IL. Stage Manager windows use the same layouts as SV or IL |

Closed landscape isn't a configuration: the outer display stays portrait-only
(decision 2).

Fold and unfold transitions aren't static states. Each gets a three-frame
storyboard (§5, rule 7).

## 4. Screen and state inventory

Read from the code at `fd6675b`: 16 screens plus the shared banners,
**165 states**. Phase 2 re-checks this list, and any state found there that is
missing here is added before mockups start.

| # | Screen (file) | States |
|---|---|---|
| S01 | Launch / loading (`RootView`) | a blank · b loading · c first launch offline · d load error (Try Again / Sign Out) · e sign-out failed banner |
| S02 | Sign in (`SignInView`) | a empty (buttons disabled) · b filled · c keyboard up · d busy · e wrong password · f offline · g dev-account footer |
| S03 | Account sheet (`AccountView`) | a up to date · b syncing · c N waiting to upload · d offline (Sign Out disabled) · e offline, N waiting · f server error · g nothing to reset · h reset confirmation · i dev-account footer · j toast after reset · k error banner |
| S04 | Puzzles home (`PuzzlesHomeView`) | a populated (resume, review count, In progress chip) · b no session, nothing to review · c collections but no puzzles (Practice hidden) · d empty · e empty offline · f offline · g context menu · h swipe delete · i rename alert · j delete confirmation |
| S05 | Import puzzles sheet (`ImportView`) | a nothing yet · b parsed, existing collection · c parsed, new collection · d rejected rows · e all rows rejected · f several collections · g source error · h busy · i offline · j keyboard in editor · k Files picker |
| S06 | Collection (`CollectionView`) | a stats card · b session in progress (Resume, Discard) · c ⋯ menu · d empty · e rename alert · f delete confirmation · g offline |
| S07 | Puzzle list (`PuzzleListView`) | a default · b searching · c scope applied · d empty scope · e no search results · f no puzzles · g swipe actions · h delete confirmation · i offline |
| S08 | Puzzle detail (`PuzzleDetailView`) | a move puzzle at start · b stepping a solution · c several solution lines · d missing piece · e flagged · f ⋯ menu · g comment sheet · h delete confirmation · i offline |
| S09 | Session (`SessionView`, `PuzzleSolveView`, `MissingPieceSolveView`, `ResultCard`, `PiecePicker`) | a your move · b wrong move · c answer shown · d opponent replying · e promotion picker · f missing piece: tap square · g missing piece: choose piece · h missing piece: hint · i solved · j solved, several lines · k missed · l long result (card scrolls) · m session complete · n flagged · o offline |
| S10 | Puzzle analysis (`PuzzleAnalysisView` → scratch `GameContentView`) | a solution preloaded · b missing piece placed · c ⋯ menu · d Save as Game: existing collection · e Save as Game: new collection · f offline. Board states are as S15 |
| S11 | Games home (`GamesHomeView`) | a populated · b empty · c empty offline · d new collection alert · e context menu · f swipe actions · g rename alert · h delete confirmation · i offline |
| S12 | Game collection (`GameCollectionView`) | a browse · b search, no match · c + menu · d ⋯ menu · e edit mode, none selected · f edit mode with selection + bulk bar · g all selected · h reorder drag · i move/copy destination sheet · j rename alert · k delete collection confirmation · l delete selected confirmation · m empty · n empty offline · o offline · p edit mode offline · q share sheet |
| S13 | Import PGN sheet (`ImportPGNView`) | a nothing yet · b games read · c more than 5 games · d read errors · e source error · f busy · g offline · h keyboard · i Files picker |
| S14 | New Game sheet (`NewGameView`) | a standard start · b from FEN, empty · c valid FEN · d invalid FEN (board dimmed) · e keyboard · f offline |
| S15 | Analysis view (`GameView`) | a default with eval bar · b evaluation hidden · c engine lines · d engine starting · e comment card · f alternatives (≤ 3) · g alternatives expanded · h variations in the list · i no moves yet · j at start / at end · k promotion picker · l move context menu · m delete-from-here confirmation · n ⋯ game menu · o delete game confirmation · p unsaved, back alert · q unsaved, offline discard alert · r offline · s illegal-move problem · t unreadable PGN · u unreadable PGN offline · v densest case (engine lines + comment + alternatives) |
| S16 | Analysis sheets (`CommentSheet`, `GameDetailsSheet`) | a comment, empty · b comment with text (Remove Comment) · c comment at large detent · d comment keyboard · e details · f details keyboard · g share sheet |
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

Apple's "Designing for iPhone Duo" HIG page is the authority here. Its text
wasn't readable by fetch, so Phase 0 reads it in a browser and corrects this
list where they differ.

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
   screens. Every toolbar item has a title and a symbol. Ellipsis means overflow
   only. Custom bars check `toolbarVerticalEdge`.
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

**Phase 2 — Capture today.** Run every screen × configuration and screenshot it,
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

**Phase 3 — Audit.** For each captured cell, list where it breaks the §6
checklist or wastes the screen. Output is a findings table (screen · config ·
issue · checklist item · severity), appended to this file, starting from the §2
rows. Re-check the §4 inventory against the code at the same time.

**Phase 4 — Mockups.** Build the canvases to the §5 rules, in the order Analysis
(riskiest), Session and detail, Shell and homes, then the rest. Share the link
after each canvas so the direction can be corrected early. Check every frame
against §6, then fill the coverage grid.

**Phase 5 — Review.** Settle §10 with the user, update the mockups, and record
the decisions here (like §7 of the refresh plan).

**Phase 6 — Slices.** Turn the approved mockups into build prompts (§9) in the
existing format (`scripts/run-ios-*-prompts.sh`).

## 9. Implementation slices (sketch, for after the mockups)

| Slice | Scope |
|---|---|
| D01 | Build with Xcode 27.1 (`runs-on: xcode-27`) in CI and TestFlight, with a regression pass on a normal iPhone; `Info.plist` orientations per decisions 2, 3 and 6; iPhone Duo simulator in UI tests |
| D02 | One `NavigationSplitView` per tab; shared navigation model; toolbar titles and overflow; continuity on fold and unfold |
| D03 | Puzzles columns (S04, S06, S07, S08 in the detail column) |
| D04 | Games columns (S11, S12) |
| D05 | Board layout rule and height caps; Analysis view controls aware of `toolbarVerticalEdge` |
| D06 | Puzzle detail and session two-pane, with the result card in the trailing pane |
| D07 | Folded poses: `ReservedRegion` division handling for the board screens (FB/FT) |
| D08 | Sheets, overlays, banners and toasts clear of the side bar and fold; sign-in and loading column |
| D09 | Screenshot tests: every mockup cell as a route × simulator pose |
| D10 | Polish: Dynamic Type AX5, dark mode, Reduce Transparency, VoiceOver order across panes |
| D11 | iPad: device family, orientations, iPad simulator in CI, spot checks, including Stage Manager window sizes |

## 10. Decisions

1. **Hardware: available.** The user has an iPhone Duo for TestFlight checks.
2. **Outer display landscape: no.** The outer display stays portrait-only.
3. **Split View: take part.** What it requires of `Info.plist` depends on Phase 1.
4. **Regular-width shell: tab bar + `NavigationSplitView`.** `.sidebarAdaptable`
   is still drawn once for comparison.
5. **Analysis view on the outer display: option A.** The side bar stays, and the
   system layout is kept. If the measured board stays under 352 pt with the eval
   bar on, that frame records it as an accepted exception to §6.6.
6. **iPad: in scope.** It is cheap: one slice (D11) after the regular-width work,
   with no iPad-specific screens.
7. **Two Motif windows: not built.** No clear use case, and the split view
   columns already show a list beside its detail.

## 11. Done when

- §3 has measured values for every configuration, and §4 has been re-checked
  against the code.
- The Phase 2 screenshot grid and Phase 3 findings table are in this file.
- The canvases cover every cell required by §5, with no blank cell in the
  coverage grid. Each frame passes the §6 checklist (or records an accepted
  exception), and the links are at the top of this file.
- §10 decisions are recorded, and §9 is ready to become build prompts.

## 12. Sources

- [Apple — Designing for iPhone Duo (HIG)](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) (not yet read in full)
- [Apple — iPhone Duo tech talk](https://developer.apple.com/videos/play/tech-talks/111466/)
- [Apple Developer Forums — iPhone Duo group lab summary](https://developer.apple.com/forums/thread/847644)
- [Apple — iPhone Duo Tech Specs](https://support.apple.com/en-us/148588)
- [GitHub runner images — Xcode 27 image contents](https://github.com/actions/runner-images/blob/releases/xcode-27-arm64/20261026/images/macos/xcode-27-arm64-Readme.md)
- [GitHub runner images — `xcode-27` label](https://github.com/actions/runner-images/issues/14404)
- [Figma Forum — 890 × 626 vs 951 × 669](https://forum.figma.com/report-a-problem-6/iphone-duo-open-preset-is-890-626-but-apple-s-kit-and-app-store-connect-point-to-951-669-59341)
- [Blake Crosley — iPhone Duo for developers](https://blakecrosley.com/blog/iphone-duo-for-developers)
- [MacRumors — iPhone Duo roundup](https://www.macrumors.com/roundup/iphone-duo/)
