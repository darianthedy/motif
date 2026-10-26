# Motif — iOS UI Refresh Plan

> Brings every iOS screen in line with iOS 26 conventions (Liquid Glass bars,
> toolbar actions, `ContentUnavailableView`, native edit mode, sheets with
> ✕/✓ toolbars). Only the presentation changes: the model, data layer and
> PGN/puzzle logic stay as they are.
>
> **Mockups:** https://claude.ai/artifact/LWDMhxnGuDKZFqkdQ79QCb — one board
> for every screen and state below, laid out in rows that match the sections
> of this plan. The game viewer was already redesigned in PR #20 (mockups:
> https://claude.ai/artifact/2j2hQoU7Nq6bxfLgyEZuor), so it only gets the
> shared fixes here.

---

## 1. What's there today

Deployment target is iOS 26.1, so every API named below is available without
availability checks.

| # | Screen (file) | States the code can reach today |
|---|---|---|
| 1 | Launch (`RootView`) | `unknown` (blank), `waiting` + loading spinner, `waiting` + offline message, `waiting` + error message |
| 2 | Sign in (`SignInView`) | idle, dev-account note, busy (“Working…”), error text, offline (buttons disabled + note) |
| 3 | Account tab (`AccountView`) | up to date, syncing, N results waiting, offline (+ pending), server error, dev-account note, sign-out disabled offline |
| 4 | Puzzles home (`PuzzlesHomeView`) | empty, collections list with progress + “in progress” tag, resume random session, review mistakes (n / disabled), reset confirmation, offline note |
| 5 | Import sheet (`ImportView`) | empty, parsed (count), rejected rows, several collections in one file, pick existing / new collection, busy, offline |
| 6 | Collection (`CollectionView`) | stats line, session in progress (resume / discard), solve buttons disabled when empty, rename alert, delete confirmation, offline |
| 7 | Puzzle list (`PuzzleListView`) | filter picker (All/New/To review/Solved/Flagged), rows with flag + status; **no empty state** for a filter with no matches |
| 8 | Puzzle detail (`PuzzleDetailView`) | move puzzle with replay, several solution lines, missing-piece answer, inline comment editor + save, flag/unflag, delete confirmation, offline |
| 9 | Session (`SessionView` + solve views + `ResultCard`) | your move, wrong move (shake + haptic), answer shown after misses, opponent replying, promotion picker, missing-piece placement + picker, result solved / missed, session complete, Stop / Flag / Skip |
| 10 | Games home (`GamesHomeView`) | empty, list, new-collection alert, offline |
| 11 | Game collection (`GameCollectionView`) | Browse / Select / Reorder segmented modes, search, no games / no match, bulk move-copy-export-delete, ↑/↓ reorder buttons, export, rename, delete, offline |
| 12 | Add games sheet (`AddGamesView`) | paste/choose PGN, read count + errors, first five titles, start-position FEN + validation, “New game on the board” |
| 13 | Game viewer (`GameView`, PR #20) | already iOS 26 native; plus the unreadable-PGN fallback, comment sheet, details sheet |
| — | Shared (`Banners.swift`) | offline banner, server-error banner, notice banner (tap to dismiss), `OfflineNote` footers |

## 2. Where it departs from iOS conventions

1. **Actions live in list rows.** “Import puzzles”, “New collection”, “Add games”,
   “Rename collection”, “Delete collection”, “Reset progress” and “Sign out” are
   plain `Button` rows at the bottom of lists. iOS puts creation in a toolbar
   **+** and secondary/destructive actions in a toolbar **⋯** `Menu`.
2. **Empty states are a grey sentence in a list.** iOS uses
   `ContentUnavailableView` with a symbol, title, description and one action.
   The puzzle list has no empty state at all.
3. **Home-made modes instead of edit mode.** The game collection’s
   Browse/Select/Reorder segmented picker plus ↑/↓ buttons re-implements what
   `List(selection:)` + `.onMove` + `EditButton` give for free (drag handles,
   selection circles, bottom-bar bulk actions).
4. **Search and filters.** Game search is a `TextField` row and the puzzle filter
   is a `Picker` row; iOS uses `.searchable` and (for puzzles) `searchScopes`.
5. **Sheets confirm in the body.** Import sheets put “Add N puzzles/games” as a
   form row. iOS puts ✕ in `cancellationAction` and a ✓ in
   `confirmationAction`, disabled until valid (the game sheets already do this).
6. **Account is a tab.** A tab for one settings form is heavy; iOS 26 apps
   (App Store, Music, Podcasts) open an account sheet from an avatar button.
7. **Tab bar hidden on every push.** `.toolbar(.hidden, for: .tabBar)` on all
   drill-downs is non-standard; keep the bar on list screens, hide it only where
   the board needs the room (puzzle detail, game viewer) and let it minimise on
   scroll (`.tabBarMinimizeBehavior(.onScrollDown)`).
8. **Notices are banners you must tap away.** Successes (“Added 24 puzzles.”)
   should be a transient toast that dismisses itself; only errors stay.
9. **Repeated offline footers.** `OfflineNote` appears in five places. A single
   offline status (home subtitle pill + disabled controls) is enough.
10. **Tint contrast.** `motifAccent` (#6EAB47) on white is ~2.6:1, below the
    4.5:1 needed for text buttons. Use `motifAccentStrong` (#3D7A1F, ~5.4:1) as
    the app tint and keep the lighter green for fills (progress rings, bars).
11. **Puzzle detail edits inline.** A `TextEditor` + “Save comment” button in a
    scroll view; the game viewer already uses a comment sheet — reuse it.
12. **Session chrome.** “Stop / Flag / Skip” are three text buttons crowded in the
    nav bar; the result card sits in the scroll flow under the board.

## 3. Shared changes (do first)

- **App tint** → `Color.motifAccentStrong`; keep `motifAccent` for fills only.
- **Toast**: replace `NoticeBanner` with a glass capsule above the tab bar,
  auto-dismissing after ~3 s, VoiceOver-announced
  (`AccessibilityNotification.Announcement`). Errors (“That didn’t save…”)
  keep a persistent banner with a dismiss button.
- **Offline**: drop `OfflineNote` footers; show one “Offline · N results waiting”
  pill under the large title on the two home screens, and disable edit controls
  (they already disable). Keep `offline-banner` as the pill’s identifier.
- **Empty states**: one helper around `ContentUnavailableView` used by every
  empty list (§4).
- **Two tabs** (Puzzles, Games) + an **account avatar** in each home toolbar
  that presents the Account sheet. Remove the Account tab.
- **Tab bar** visible on list screens; hidden on puzzle detail, game viewer and
  sessions. Add `.tabBarMinimizeBehavior(.onScrollDown)`.
- **Sheets**: every form sheet uses ✕ (`cancellationAction`) and a prominent ✓
  (`confirmationAction`), `.presentationDetents` where content is short.
- **Accessibility identifiers**: keep every identifier the UI tests use
  (`import-puzzles`, `puzzle-import-add`, `solve-ordered`, `resume-session`,
  `session-skip`, `session-stop`, `result-continue`, `result-verdict`,
  `game-search`, `game-import-add`, `game-actions`, `offline-banner`, …) on the
  control that now does that job, so `MotifUITests` only needs navigation
  changes (menus instead of rows).

## 4. Screen by screen

### Sign in, loading, account — mockup row 1

**Sign in.** Centered app mark, “Motif” title and one-line pitch; email and
password in one inset group; full-width prominent **Sign In** pinned near the
bottom, **Create Account** as a plain button under it. Errors show inline under
the fields with an icon (`role=alert`). Offline shows a grey pill above the
fields and disables both buttons. The dev-account note becomes a footer under
the fields in dev builds only.
States: default · wrong password · offline. (Busy: the Sign In label swaps for
a `ProgressView`.)

**Loading.** `ProgressView("Loading your library…")` while loading;
`ContentUnavailableView` “You’re Offline” (wifi.slash) for a first launch
offline; “Couldn’t Load Your Library” with **Try Again** (re-runs
`store.open()`) and **Sign Out** on error — today there is no way out of the
error state.

**Account sheet** (from the avatar). Avatar initial + email header; **Sync**
section with one status row (Up to date / Syncing… / Offline · N waiting /
Couldn’t reach the server); **Progress** section with **Reset Puzzle
Progress…** (moved here from Puzzles home) and its explanation as a footer;
**Sign Out** row; version footer. Reset uses a confirmation dialog.
States: default · offline with results waiting · reset confirmation.

### Puzzles library — mockup row 2

**Puzzles home.** Large title + subtitle “48 puzzles in 3 collections”; toolbar
**+** (import) and avatar.
- *Practice* section: Resume Random Session (only when one exists, trailing
  “7 left”), Random From Everything, Review Mistakes (count badge; disabled at 0).
  Settings-style icon tiles.
- *Collections* section: progress ring, name, “24 puzzles · 18 solved · 3 to
  review”, an “In progress” tag, chevron. Swipe to delete, context menu
  Rename / Delete.
States: populated · empty (`ContentUnavailableView` + **Import Puzzles**) ·
offline (pill, **+** disabled) · toast after an import.

**Import sheet.** ✕ / “Import Puzzles” / ✓ (disabled until something parses).
Source group: **Choose File…** and **Paste From Clipboard** (new; reads
`UIPasteboard`), then the monospaced JSON editor. *Found* section with a
check/warning row and each rejected row in red. *Add to* section: collection
menu picker + name field, footer explaining refresh-not-duplicate. With several
collections in one file the section lists them instead.
States: nothing yet · file read · rejected rows + several collections.

**Collection.** Large title; ⋯ menu (Rename…, Import Into Collection…, Delete
Collection). A stats card (Solved / To review / New with a stacked bar) replaces
the footnote line. *Session in progress* card with a **Resume** capsule and
**Discard Session**. *Solve* group: Solve in Order, Solve Shuffled. Separate
**All Puzzles** row with count.
States: default · session in progress · ⋯ menu · no puzzles (empty view with
**Import Puzzles**).

### Browsing puzzles — mockup row 3

**Puzzle list.** Large title “All Puzzles”, subtitle with the collection; native
`.searchable` (number or motif tag) with `searchScopes` All / New / Review /
Solved / Flagged. Rows get a 48 pt board thumbnail (`BoardView` non-interactive,
no coordinates), number, “Mate in 2 · back rank · 1450” subtitle, flag glyph and
a status glyph + word. Swipe actions: Flag (orange), Delete (red, confirmed).
States: default · swipe actions · empty scope (“No Flagged Puzzles”).

**Puzzle detail.** Inline title “#00412” with the collection as subtitle; toolbar
Flag toggle + ⋯ (Copy FEN, Delete Puzzle). Full-width board; solution moves as
selectable chips (segmented Line 1/Line 2 above them when there are several);
an info group (Status with attempts/mistakes, Motif, Rating, Comment row). The
replay controls move to a bottom glass bar matching the game viewer. Tapping
Comment opens the existing `CommentSheet` (✕/✓, Remove Comment) instead of the
inline editor.
States: move puzzle · missing piece (Answer row, no replay bar) · comment sheet.

### Solving a session — mockup row 4

Full-screen cover. Nav: ✕ (End session, keeps `session-stop`), title = scope
name with “Puzzle 4 of 24” subtitle, Flag toggle on the right. A thin progress
bar under the nav. Board full width. Under it a capsule prompt with the side to
move and one line of guidance; a **Skip** glass button bottom-right.
- Wrong move: shake + error haptic (as today); after the threshold the answer
  squares turn orange and the guidance reads “Not quite. Play the highlighted
  move.” in orange.
- Promotion / placement: the existing `PiecePicker`, restyled as a glass card
  over a dimmed board (“Promote to”, “Add on f6”).
- Result: a glass sheet rises over the lower half: verdict with icon, misses
  (“1st Qe7 → Qe8+”), the solution line with a “Your line” tag, comment, tags,
  and a full-width **Continue**. Skip hides while it shows.
- Complete: big check, “Session Complete”, two stat tiles (solved cleanly /
  missed), **Done**.
States: your move · answer shown · promotion · solved · missed · missing piece
(tap a square) · missing piece (choose piece) · complete.

### Games — mockup row 5

**Games home.** Large title + subtitle; toolbar **+** (new collection alert) and
avatar; rows with an icon tile and game count; swipe/context menu Rename and
Delete. States: populated · empty (`ContentUnavailableView` + **New
Collection**) · new-collection alert.

**Game collection.** Large title + count; `.searchable` (players, event,
opening); rows show title, “event · round · date · opening” and a result chip.
Toolbar **+** menu: Import PGN…, New Game on Board…; **⋯** menu: Select Games,
Export as PGN, Rename…, Delete Collection.
**Edit mode** (Select Games) replaces Browse/Select/Reorder: selection circles,
drag handles (`.onMove` → `shiftGame`/`placeGames`), nav shows Select All /
“2 Selected” / ✓ Done, and a bottom glass bar with Move, Copy, Export, Delete.
Move and Copy open a destination sheet (current collection disabled).
States: browse · + menu · select & reorder · move-to sheet · empty (Import PGN
+ New Game on Board).

**Import PGN sheet** (split out of Add games). ✕ / “Import PGN” / ✓ “Add N”.
Choose Files…, Paste From Clipboard, PGN editor, *Found* section with errors and
up to five titles. States: nothing yet · games read.

**New Game sheet** (split out of Add games). Segmented Standard Start / From a
FEN, a live board preview of the position, FEN field with an inline validation
footer; ✓ disabled while invalid. Creating opens the game viewer as today.
States: default · invalid FEN.

**Game viewer.** Unchanged from PR #20, except the unreadable-PGN fallback
becomes a `ContentUnavailableView` (“Can’t Read This Game”) with **Copy PGN**
and **Delete**, and the raw PGN in a card below.

## 5. Implementation slices

Each slice is one PR, sized like the P-prompts, with `MotifTests` +
`MotifUITests` green. The runnable prompt for each slice is in §8.

| Slice | Scope | Main files |
|---|---|---|
| **U01** Shared foundation | Tint swap, toast + error banner, offline pill, empty-state helper, sheet toolbar helper, tab bar minimise/visibility rules | `RootView`, `Banners.swift`, new `UI/Shared/Toast.swift`, `EmptyState.swift` |
| **U02** Account sheet | Two tabs + avatar button, Account sheet with sync/reset/sign-out, remove Account tab; move Reset from Puzzles home | `RootView`, `AccountView`, `PuzzlesHomeView`, `GamesHomeView`, `AppState` (`showingAccount`) |
| **U03** Sign in + loading | New sign-in layout, loading/offline/error with Try Again and Sign Out | `SignInView`, `RootView` |
| **U04** Puzzles home + import | Practice/Collections sections, progress rings, + toolbar, swipe/context menus, import sheet ✕/✓ + paste | `PuzzlesHomeView`, `ImportView` |
| **U05** Collection + puzzle list | Stats card, ⋯ menu, session card; `.searchable` + scopes, thumbnails, swipe actions, empty scope | `CollectionView`, `PuzzleListView` |
| **U06** Puzzle detail | Header, chips, info group, bottom replay bar, comment sheet reuse, ⋯ menu | `PuzzleDetailView`, `CommentSheet` |
| **U07** Session | Nav/progress, prompt capsule, Skip button, picker restyle, result sheet, complete screen | `SessionView`, `PuzzleSolveView`, `MissingPieceSolveView`, `ResultCard`, `PiecePicker` |
| **U08** Games home + collection | + / ⋯ toolbars, `.searchable`, native edit mode with bulk bar, move/copy destination sheet | `GamesHomeView`, `GameCollectionView` |
| **U09** Import PGN + New Game | Split `AddGamesView` into two sheets, board preview for FEN | `AddGamesView` → `ImportPGNView`, `NewGameView` |
| **U10** Polish | Unreadable-game view, Dynamic Type pass (largest sizes), dark mode pass, VoiceOver labels, update UI tests and screenshot routes | `GameView`, `MotifUITests/*`, debug routes in `AppState` |

Order matters only for U01 (everything depends on it) and U02 (moves Reset out
of Puzzles home before U04 rewrites it). U03–U09 are otherwise independent.

## 6. Tests

- The debug `MotifRoute` launch routes stay; add `account`, `puzzle-list-empty`,
  `game-select`, `game-new` for the new states, and capture every mockup state
  as a simulator screenshot in U10 to compare against the canvas.
- UI tests that tap list-row buttons (“Import puzzles”, “Add games”, “New
  collection”) switch to the toolbar button with the same identifier.
- `GameCollectionModel.mode` and its tests go away with the native edit mode;
  bulk move/copy logic (`moveGames`, `copyGames`, `shiftGame`) stays and keeps
  its model tests.

## 7. Decisions (confirmed 2026-10-27)

1. **Account tab → avatar sheet.** Two tabs (Puzzles, Games); Account opens as a sheet.
2. **Reset progress lives in Account**, not on Puzzles home.
3. **Paste From Clipboard** in both import sheets (accepting the first-use paste prompt).
4. **Puzzle search** by number and motif tag, with the status filters as search scopes.
5. Session complete shows only Done; a “Review N Mistakes” shortcut is a later follow-up.

---

## 8. Running the slices

Same process as the build prompts: **one fresh Claude session per slice**, in
order, each ending in a PR with `ios-ci` green (it runs `MotifTests` and
`MotifUITests`), then merge.

- **Unattended:** from a clean, dedicated checkout on `main`, run
  `scripts/run-ios-ui-prompts.sh` (all slices) or `scripts/run-ios-ui-prompts.sh U04`
  (resume at U04). It reuses `run-ios-prompts.sh`: branch `ios-ui/Uxx`, PR, CI
  fix loop, merge, TestFlight check (`SKIP_TESTFLIGHT=1` to skip that wait).
- **By hand:** open a new session in the repo, paste the slice’s **Run** line,
  review the PR, merge, then start the next slice in a new session.

### Shared rules (inlined into every slice)

> 1. **UI only.** Do not change `Model/`, `Data/`, or the behaviour `src/` defines.
>    View models may change shape; the rules they enforce may not.
> 2. **The screen descriptions in §3–§4 are the spec.** The mockups
>    (https://claude.ai/artifact/LWDMhxnGuDKZFqkdQ79QCb, board names given per
>    slice) show the target; read them if your tools can open claude.ai artifacts.
>    Use system components (`List`, `Menu`, `.searchable`, `ContentUnavailableView`,
>    `.toolbar`, `.sheet`, `.glassEffect`) rather than hand-drawn look-alikes.
> 3. **Keep accessibility identifiers** the UI tests use, on whatever control now
>    does that job. Update `MotifUITests` in the same slice for any navigation you
>    change (e.g. a row button becoming a toolbar button or menu item).
> 4. **Never show tags, comments or motif while solving.**
> 5. **Synchronized folders:** new files under `Motif/`, `MotifTests/`,
>    `MotifUITests/` need no `project.pbxproj` edit.
> 6. **No Mac, so CI is the compiler.** Done = `ios-ci` green + the slice’s
>    “Done when” + nothing from a later slice.

### U01 — Shared foundation

**Run:**
> In this repo, read `Motif - iOS UI Refresh Plan.md` §2, §3 and §8 → **U01**.
> Build the shared UI foundation: tint swap, toast, error banner, offline pill,
> empty-state helper, sheet toolbar helper, tab bar rules. Get `ios-ci` green.

**Build:** `UI/Shared/Toast.swift` (glass capsule, ~3 s auto-dismiss, VoiceOver
announcement), error banner kept persistent in `Banners.swift`, an
`OfflinePill` (identifier `offline-banner`), `UI/Shared/EmptyState.swift`
(wrapper over `ContentUnavailableView` with one optional action), a sheet
toolbar helper (✕ cancel / prominent ✓ confirm); app tint → `motifAccentStrong`;
`.tabBarMinimizeBehavior(.onScrollDown)`; tab bar visible on list screens and
hidden only on puzzle detail, game viewer and sessions. `app.notice` successes
go to the toast, failures to the banner.
**Out of scope:** restyling any individual screen; removing `OfflineNote` from
screens other than where the pill replaces it (later slices do it per screen).
**Done when:** existing screens still work with the new tint/toast/banner; CI green.

### U02 — Account sheet and two tabs

**Run:**
> In this repo, read `Motif - iOS UI Refresh Plan.md` §3, §4 “Account sheet”,
> §7 and §8 → **U02**. Replace the Account tab with an avatar button that opens
> the Account sheet, and move Reset Progress into it. Get `ios-ci` green.

**Mockups:** `Account`, `AccountOffline`, `AccountReset`.
**Build:** `AppState.showingAccount`; avatar toolbar button on Puzzles and Games
home; `AccountView` as a sheet (avatar header, Sync status row, Progress section
with Reset Puzzle Progress… + confirmation, Sign Out, version footer); remove the
Account tab and the Reset button from Puzzles home; the debug `account` route
opens the sheet.
**Done when:** sign out, reset and sync status work from the sheet; UI tests
updated; CI green.

### U03 — Sign in and loading

**Run:**
> In this repo, read `Motif - iOS UI Refresh Plan.md` §4 “Sign in”, “Loading”
> and §8 → **U03**. Restyle sign-in and the loading/offline/error root states,
> adding Try Again and Sign Out to the error state. Get `ios-ci` green.

**Mockups:** `SignIn`, `SignInError`, `SignInOffline`, `Loading`,
`LoadingOffline`, `LoadingError`.
**Keep:** `auth-email`, `auth-password`, `sign-in`. Dev-account note only when
`usingDevAccount`.
**Done when:** Try Again re-runs `store.open()`; Sign Out works from the error
state; CI green.

### U04 — Puzzles home and import

**Run:**
> In this repo, read `Motif - iOS UI Refresh Plan.md` §3, §4 “Puzzles home”,
> “Import sheet” and §8 → **U04**. Rebuild Puzzles home (Practice + Collections,
> progress rings, + toolbar, swipe/context menus, empty state) and the import
> sheet (✕/✓, Paste From Clipboard). Get `ios-ci` green.

**Mockups:** `Main`, `PuzzlesEmpty`, `PuzzlesOffline`, `PuzzlesToast`, `Import`,
`ImportParsed`, `ImportErrors`.
**Keep:** `import-puzzles` (now the + button), `solve-all`, `collection-<id>`,
`puzzle-import-text`, `puzzle-import-add` (now the ✓), `import-collection-name`.
**Done when:** import from file, paste and typed JSON all work; rename/delete from
the row menu work; CI green.

### U05 — Collection and puzzle list

**Run:**
> In this repo, read `Motif - iOS UI Refresh Plan.md` §4 “Collection”, “Puzzle
> list” and §8 → **U05**. Rebuild the collection screen (stats card, ⋯ menu,
> session card) and the puzzle list (`.searchable` with scopes, thumbnails,
> swipe actions, empty scope). Get `ios-ci` green.

**Mockups:** `Collection`, `CollectionResume`, `CollectionMenu`,
`CollectionEmpty`, `PuzzleList`, `PuzzleListSwipe`, `PuzzleListNoMatch`.
**Keep:** `solve-ordered`, `resume-session`, `browse-puzzles`, `puzzle-<id>`.
“Import Into Collection…” opens the import sheet with this collection preselected.
Search matches `#sourceId` and motif tags.
**Done when:** search + scopes filter correctly (add a view-model test); swipe
flag/delete work; CI green.

### U06 — Puzzle detail

**Run:**
> In this repo, read `Motif - iOS UI Refresh Plan.md` §4 “Puzzle detail” and §8
> → **U06**. Rebuild puzzle detail: header with Flag + ⋯, move chips, info
> group, bottom replay bar, comment via `CommentSheet`. Get `ios-ci` green.

**Mockups:** `PuzzleDetail`, `PuzzleDetailMissing`, `PuzzleDetailComment`.
**Keep:** `edit-puzzle-comment` on the sheet’s text view.
**Done when:** replay, line switching, flag, copy FEN, delete and comment save
work; CI green.

### U07 — Solving session

**Run:**
> In this repo, read `Motif - iOS UI Refresh Plan.md` §4 “Solving a session” and
> §8 → **U07**. Restyle the session: nav + progress, prompt capsule, Skip button,
> glass piece picker, result sheet, complete screen. Get `ios-ci` green.

**Mockups:** `Solve`, `SolveHint`, `SolvePromotion`, `SolveSolved`,
`SolveFailed`, `SolveMissing`, `SolveMissingPicker`, `SolveComplete`.
**Keep:** `session-stop`, `session-skip`, `result-verdict`, `result-continue`,
`puzzle-comment`, `puzzle-tags`, `choose-*`, `picker-cancel`; `SolveModel`
timing (`REPLY_MS`) and the drag/scroll behaviour from PR #22.
**Done when:** every solve UI test passes unchanged in intent; CI green.

### U08 — Games home and game collection

**Run:**
> In this repo, read `Motif - iOS UI Refresh Plan.md` §4 “Games home”, “Game
> collection” and §8 → **U08**. Add + / ⋯ toolbars and `.searchable`, and replace
> Browse/Select/Reorder with native edit mode, a bulk bottom bar and a Move/Copy
> destination sheet. Get `ios-ci` green.

**Mockups:** `GamesHome`, `GamesEmpty`, `GamesNewAlert`, `GameCollection`,
`GameCollectionAdd`, `GameCollectionEdit`, `GameCollectionMove`,
`GameCollectionEmpty`.
**Keep:** `new-game-collection`, `game-collection-name`, `game-collection-<id>`,
`game-search`, `add-games` (now the + menu), `game-row-<id>`. Until U09 lands,
both + menu items open the existing `AddGamesView`.
**Done when:** drag reorder persists via `placeGames`; bulk move/copy/export/delete
work; `GameCollectionModel.mode` removed with its tests adjusted; CI green.

### U09 — Import PGN and New Game sheets

**Run:**
> In this repo, read `Motif - iOS UI Refresh Plan.md` §4 “Import PGN sheet”,
> “New Game sheet” and §8 → **U09**. Split `AddGamesView` into `ImportPGNView`
> and `NewGameView` (live board preview, inline FEN validation). Get `ios-ci` green.

**Mockups:** `ImportPGN`, `ImportPGNParsed`, `NewGame`, `NewGameInvalid`.
**Keep:** `game-import-text`, `game-import-add` (now the ✓), `game-start-fen`,
`game-new-board` (now the ✓ on New Game). `AddGamesModel` logic is reused, not
rewritten.
**Done when:** both sheets work from the + menu and the empty state; creating a
new game still opens the viewer; CI green.

### U10 — Polish

**Run:**
> In this repo, read `Motif - iOS UI Refresh Plan.md` §4 “Game viewer”, §6 and §8
> → **U10**. Add the unreadable-game view, then do the Dynamic Type, dark mode and
> VoiceOver passes and add the new debug routes. Get `ios-ci` green.

**Mockups:** `GameUnreadable`.
**Build:** `ContentUnavailableView` fallback with Copy PGN / Delete; check every
screen at the largest Dynamic Type size and in dark mode; debug routes
`account`, `puzzle-list-empty`, `game-select`, `game-new`; remove any leftover
`OfflineNote` usages.
**Done when:** no clipped text at AX sizes on list screens; CI green.
