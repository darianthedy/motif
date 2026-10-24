# Database

The database is the source of truth. `0001_schema.sql` and `0002_games.sql`
are the whole of it: six tables, row-level security, and grants. No triggers,
no server code.

## Tables

- `collections` — `id` (set by the device that creates it), `name`,
  `created_at`. Names are only a label: two collections may share one, and
  renaming is an `UPDATE`.
- `puzzles` — each belongs to exactly one collection and is deleted with it.
  Unique on `(collection_id, content_key)`, which is the conflict target when a
  file is re-imported into the same collection: the upsert updates the puzzle
  instead of adding it again.
- `runs` — a session: scope (a collection id, `all` or `review`), mode, queue
  and start time. Never updated. One per scope per user: a device starting a
  new run deletes the older one in its scope, then inserts with
  `ON CONFLICT (user_id, scope) DO NOTHING`, so the newer start wins whichever
  device uploads last.
- `attempts` — one per puzzle played: `solved`, `failed` or `skipped`, with
  mistakes, whether the answer was shown, and when. Never updated. The id is
  generated on the device, so uploading the same attempt twice does nothing,
  and the outbox can always retry. Deleted with its puzzle; `run_id` is cleared
  when its run is deleted.

- `game_collections` — like `collections`, for games: `id` (set by the
  device), `name`, `created_at`. Kept apart from puzzle collections, since a
  game has no runs or progress.
- `games` — each belongs to one game collection and is deleted with it. The
  `pgn` column is the whole game — headers, moves, comments, variations — and
  an edit rewrites it. Also `position` (order in the collection) and
  `orientation` (`w` or `b`, the side at the bottom of the board). The id is
  set by the device. No dedupe key: the same game twice is two games.

Status, attempt and mistake counts, the review set and where a run has got to
are all worked out from attempts on the device (`src/model/derive.ts`), never
stored. Resetting progress deletes the account's attempts and runs.

## Privacy

Every row carries the `user_id` of its account, defaulted from the JWT by
`auth.user_id()`, and one policy per table limits every statement to the
signed-in account's rows. Foreign keys include `user_id`, so a row can only
point at a row of the same account: key checks bypass RLS, and would otherwise
let one account attach a puzzle to another's collection.

`npm test` runs both schema files in an in-process Postgres (PGlite) and checks
that a second account sees and changes nothing, cannot point at the first
account's rows, and that runs and attempts cannot be updated
(`src/data/backend.test.ts`).

## Neon setup

### 1. Never put the connection string in the app

This is the one rule. Motif is a **public** static site: anything in the bundle
is readable by anyone. A Postgres connection string is a database owner
credential, so it can only ever live server-side — which a static host does not
have. That is why this uses the Data API and JWTs rather than a direct
connection: the Data API endpoint is meant to be public and RLS does the
enforcing.

If a connection string has ever been pasted somewhere it should not be — chat,
an issue, a commit — rotate it in **Neon Console → Roles → Reset password**.
Rotation is cheap; assuming it was not captured is not.

### 2. Enable the Data API

Neon Console → your project → **Postgres database → Data API → Enable**. Tick
**Use Managed Better Auth** so there is an auth provider issuing JWTs. Note the
Data API endpoint URL it gives you.

Caveats worth knowing going in: the Data API is in Beta, it is enabled per
branch for a single database, and it is incompatible with IP Allow or Private
Networking.

### 3. Apply the schema

Paste `0001_schema.sql` into the Neon SQL Editor, then `0002_games.sql`. Doing
it in the console rather than over a connection string means no credential has
to be shared with anyone to set this up. Both files can be re-run safely, and a
database that already has the first needs only the second.

**Replacing the old sync tables.** A database set up for an earlier version of
the app has tables that clash with these. Drop them first. This deletes every
account's cloud library and progress; nothing is migrated.

```sql
drop table if exists public.sessions, public.progress, public.collection_puzzles,
  public.puzzles, public.collections, public.library_settings, public.libraries cascade;
drop function if exists public.motif_stamp, public.motif_keep_deleted,
  public.motif_merge_settings, public.motif_merge_progress, public.motif_merge_session;
drop sequence if exists public.motif_revision;
```

If the Data API doesn't see the new tables straight away, refresh its schema
cache from the Data API page.

### 4. Give the deployed app its base URL

Only the *base* URL is configured. The client derives both the auth service and
the Data API from it by inserting `neonauth` / `apirest` into the hostname, so
there is one value to get right instead of two that must agree:

```bash
gh secret set VITE_NEON_BASE_URL --body "https://<endpoint>.<region>.aws.neon.tech/neondb"
```

Read at build time and inlined into the bundle. The deploy fails without it
rather than shipping the in-memory stand-in. That is fine: the endpoint is
public by design, and RLS is the security boundary.

### 5. Trust the deploy origin

Neon Auth rejects requests from origins not on its trusted-domain list, and
**localhost is trusted by default**. So a local sync test proves nothing about
the deployed site — this exact gap shipped once, and production failed with
`Invalid origin` while every local check was green.

```bash
npx neonctl neon-auth domain add "https://<user>.github.io" --project-id <id>
```

Or Neon Console → Auth → Configuration → Domains. Origin only: scheme and host,
no path, no trailing slash.

### 6. Verify it, rather than assuming

```bash
npm run check:sync
```

Two independent browser contexts stand in for two devices — separate cookie
jars, separate IndexedDB — signed into one account. An edit on A must appear on
B, a puzzle deleted on A must disappear from B, and a run started on A while
offline must reach B once A reconnects. A third account must see none of it.

Add `--url=https://<user>.github.io/motif/` to run it against the deployed site
instead of a dev server. Do that before believing it works: the trusted-origin
rule means local success and production success are different facts.

It creates throwaway accounts. Delete them from Neon Console → Auth when done.

## Accounts are created in the app, not the console

Creating a user from the Neon Console provisions an account with no password —
Better Auth only sets one through the sign-up call. Such an account cannot sign
in here, since the app authenticates with email and password. Use **Account →
Create an account** in the app instead.
