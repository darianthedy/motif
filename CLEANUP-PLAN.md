# Motif cleanup plan

Written against `main` at 8037f51 (after PR #6 row sync and PR #7 result card).
Delete this file in the final PR.

## Principles

- **The database is the source of truth.** Every edit writes straight to its
  row. No merges, no conflict-resolving triggers, no copy of the rows "as last
  seen".
- **Only solving works offline.** The device keeps a read-only copy of the
  library to solve from, plus an outbox of attempts and runs waiting to upload.
  Both are inserts only, so they cannot conflict.
- **Clean start.** The existing cloud data and the old tables are dropped. No
  migration and no compatibility code.

## Decisions already made

- **Each puzzle belongs to exactly one collection.** The same position imported
  into two collections becomes two separate puzzles, each with its own
  progress and comment. Importing never fails, skips or removes anything
  because a puzzle exists elsewhere. The only deduplication is within one
  collection: a puzzle listed twice in a file appears once, and re-importing a
  file into the same collection updates its puzzles instead of duplicating
  them.
- **Collections are identified by id.** The id is a UUID set at creation, the
  name is just a field, and names do not have to be unique. Renaming is an
  `UPDATE`.
- **Runs (sessions) are computed from attempts.** A run stores only what never
  changes after it starts. Two devices can play the same run; the worst case
  is seeing a puzzle twice, never a conflict.
- **A skip is recorded as an attempt** with result `skipped`. It syncs and
  stops the puzzle coming back in that run, and it counts as neither solved
  nor failed.
- **Lichess CSV import is removed**, along with `setupMove`, the opponent's
  opening move that plays before your turn. It was never used. `sourceId`
  stays: it holds the puzzle number from the JSON `id` (shown as `#187`).
  `rating` stays.
- **URL import is removed.** Import is file or paste only.
- **Backup/restore is removed.** The database replaces it.
- **Sign-in is required.** There is no local-only mode any more.
- **Accepted edge case:** a reset on one device while another device has
  offline attempts waiting. Those attempts upload after the reset and show up
  as progress. No settings row to filter them out.

## Tables

New `db/0001_schema.sql`, with row-level security on `user_id` for every
table.

| Table | Columns | Notes |
|---|---|---|
| `collections` | `id uuid`, `user_id`, `name`, `created_at` | The id is set at creation. Renaming is an `UPDATE`; names do not have to be unique. |
| `puzzles` | `id uuid`, `user_id`, `collection_id` (deleted with its collection), `position`, `content_key`, `fen`, `solutions jsonb`, `add_piece`, `tags`, `comment`, `source_id`, `rating`, `added_at` | Unique on `(collection_id, content_key)`. A re-import into the same collection updates `tags`, `comment`, `rating` and `source_id`, so the file wins over an in-app comment edit. |
| `runs` | `id uuid`, `user_id`, `scope` (a collection id, `all` or `review`), `mode`, `queue uuid[]`, `started_at` | Never changed after insert. One run per scope per user; starting a new one replaces it, and the newer `started_at` wins. |
| `attempts` | `id uuid` (generated on the device), `user_id`, `puzzle_id` (deleted with its puzzle), `run_id` (set to null if the run is deleted), `result` (`solved`, `failed` or `skipped`), `mistakes`, `hinted`, `played_at` | Insert-only. Uploading the same attempt twice does nothing (`ON CONFLICT DO NOTHING`), so the outbox can always retry. |

Reset progress is `DELETE` on the user's `attempts` and `runs`.

**Computed from attempts:**
- A puzzle's status is the result of its latest attempt that wasn't a skip,
  or "unseen" if it has none.
- Its attempt and mistake counts are exact counts of its attempts.
- Review mistakes covers every puzzle whose status is failed. The run's queue
  is fixed when the run starts.
- A run's remaining puzzles are its queue minus the puzzles it has finished:
  solved, skipped, or failed and already retried.
- The progress bar and retries come from the same attempts. `RETRY_GAP` and
  `MAX_RETRIES` stay as rules applied on the device.
- The recently-seen bias for the random-from-everything draw uses the latest
  `played_at` per puzzle.
- Puzzles deleted since a run started are dropped from its queue.

## Online and offline

- **Works offline:** opening the app from the cached library, starting and
  resuming runs, solving, skipping, and browsing collections and puzzles.
- **Online only:** import, renaming and deleting collections, editing
  comments, deleting puzzles, resetting progress, and signing in or out.
  Offline, these show as disabled with a "you're offline" note.
- **Outbox:** pending attempts and runs, stored in IndexedDB. It uploads when
  the app opens, when it comes back to the foreground, when it reconnects, and
  after each solve. A run started offline uploads the same way.
- **Cache:** an IndexedDB copy of the user's collections, puzzles, runs and
  attempts. It is replaced with fresh data from the server (not merged) on
  open, on returning to the foreground, and after each online write, with the
  outbox laid on top. Keep `navigator.storage.persist()`: losing the cache
  only loses the outbox, but it is free to ask.

## Code

**New:**
- `src/data/backend.ts`: one `Backend` interface. A Neon Data API
  implementation (upserts use PostgREST `on_conflict`), and an in-memory one
  for unit tests, the e2e run, and a dev mode with no database.
- `src/data/cache.ts` and `src/data/outbox.ts`.
- `src/model/derive.ts`: status, counts, review set, run progress.

**Deleted:**
- **The current sync:** `src/model/sync.ts`, `src/model/rows.ts`,
  `src/model/rowSync.ts`, `src/useSync.ts` and their tests, plus
  `db/0001_libraries.neon.sql` and `db/0002_rows.neon.sql`.
- **Local state handling:** most of `src/model/state.ts`,
  `src/model/storage.ts` (`parseState` and its compatibility parsing), and the
  stored-session machinery in `src/model/session.ts` (`SessionState`,
  `reconcile`, the cursor). `shuffle`, the retry rules and
  `orderForGlobalDraw` stay.
- **Lichess:** `src/model/import/lichess.ts`, CSV detection in
  `ImportScreen`, and `setupMove` everywhere: board, importer, views, detail
  screen, `startingFen`, `setupMoveIsLegal`, and the `setup` phase in
  `PuzzleView`.
- **URL import:** the URL field, fetch handling and "that's a web page" check
  in `ImportScreen`.
- **Backup/restore:** Export backup and Restore from backup on Home, and
  `exportState`.
- **Unused code:** `PuzzleRunner.degenerate`, `alternativeCount`,
  `legalMoves`, `legalUci`, `piecesOn`, `missedPlies`, `firstSolvedAt`.
- **Duplicated data:**
  - The stored `mistakes` counters on both runners; compute them from
    `misses` and `wrongGuesses`.
  - The inserted/updated split in `importJson` that `applyImport` recomputes;
    the database upsert does it once.
- **Bad-data workarounds:** the "puzzle looks broken" check (`unplayable`) in
  `PuzzleView`, and the "line not playable" warnings (`truncated`) in the
  result card and puzzle detail.
- **Duplicate spellings in the JSON format:** keep `add_piece` (drop
  `addPiece`) and `id` (drop `sourceId`). Replace `isPlausibleFen` with a
  chess.js load check.

**Kept:**
- The trie, both runners, `move.ts`, and `board.ts` minus the unused functions.
- `Board.tsx`, and the result card including PR #7.
- The retry rules, the PWA config and the deploy workflow.
- The in-process Postgres test harness, `src/test/pgServer.ts`.
- `scripts/validate-external.mjs`, changed to run through `tsx` and import
  the model instead of re-implementing `parsePlacement` and the placement
  rules.

## Screens

- **Import:** file or paste. Choose the target collection: an existing one, or
  a new one with the file's `collection` name as the default. A file with
  several groups creates one new collection per group.
- **Collection:** add rename. Delete stays.
- **Home:** remove backup/restore, keep reset progress, add an offline
  indicator.
- **Account:** becomes the sign-in screen shown before anything else.
- **Session:** unchanged in look. Skip writes a `skipped` attempt.

## Delivery: three PRs

1. **Schema and data layer.** The new SQL, the `Backend` interface with both
   implementations, and `derive.ts`. Tests run against the in-process Postgres
   for the access rules (a second account sees nothing), uploading the same
   attempt twice, cascading deletes, unique `(collection_id, content_key)`,
   and one run per scope.
2. **Wiring the app.**
   - Add the cache, outbox, sign-in gate and offline handling.
   - Delete the old sync, Lichess, URL import, backup/restore and
     `setupMove`.
   - Rewrite `scripts/check-sync.mjs` as a two-device check: an edit on A
     appears on B, a delete on A disappears on B, and attempts made offline
     on A upload once A reconnects.
   - Update `scripts/e2e-solve.mjs` to run against the in-memory backend.
   - **Before dropping the old Neon tables, confirm with the user: it wipes
     the current cloud data.**
3. **Collections and cleanup.** The import target picker, rename, and the
   remaining unused code. Rewrite `README.md` and `db/README.md`, fix
   `.env.example`, and delete this file.
