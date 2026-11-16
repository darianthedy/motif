# Design review: iPhone Duo (2026-11-15)

Review of the iOS app on the iPhone Duo simulator (iOS 27.2, Xcode 27.2) at `265e097`.
Nothing in the app was changed; each finding below has a proposed fix awaiting approval.

## Findings, by severity

1. [High — Practice row breaks in the sidebar](01-practice-row-sidebar.md) (inner wide, book)
2. [High — Open tall with nothing selected hides the sidebar](02-open-tall-no-selection.md) (inner tall) — fixed
3. [Medium — Puzzle detail: replay bar covers the Comment row](03-puzzle-detail-bar-overlap.md) (inner tall)
4. [Medium — Analysis: move list hidden despite free space](04-analysis-move-list-hidden.md) (inner tall, outer)
5. [Low — Sidebar subtitle truncated](05-sidebar-subtitle-truncated.md) (inner wide)

## How it was checked

- 14 screens (sign-in, Puzzles home, collection, puzzle list, puzzle detail, session,
  import, account, Games home, game collection, New Game, Import PGN, Analysis, comment
  sheet) in light and dark, on the outer display (O), the inner display wide (IL) and
  tall (IP): 84 screenshots. Plus 5 screens half-folded in book pose (FB).
- Poses set with `duoctl`; shots with `xcrun simctl io <udid> screenshot --display=1`
  (outer) and `--display=3` (inner). Screens opened with the debug launch routes
  (`-MotifRoute`, `-MotifFixture`) on the memory backend.
- `/apple-design` in iPhone Duo mode on the screenshots; `/swiftui-pro` on the SwiftUI
  code, focused on resizing.

## What works

- Bars follow the system: side bar on O and IL, horizontal bars on IP; Back/Close first,
  then the main action, then the overflow.
- The sidebar's own items stay above the sidebar, next to their content
  (`designing-for-iphone-duo.md › Vertical controls`).
- Half-folded, boards stay on the leading page clear of the fold and sheets move to one side.
- The `…` menus are the system overflow menu on iOS 27.1.
- Nothing sits under the outer camera. Dark mode matches light everywhere.

## Not tested

- **Split View.** It can't be opened from the command line in the simulator. The code
  handles the strip at the shared edge (`BoardLayout.swift:91-95`), and the Duo plan
  records a device check. Worth a manual pass in Device Hub.
