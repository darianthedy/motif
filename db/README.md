# Sync backend

One row per thing, tied to the account by `user_id`: every puzzle, collection,
collection membership, progress entry and suspended session is its own row. No
server code beyond the schema's triggers.

- `0001_libraries.neon.sql` — the original single-blob table. Still applied
  first: the app reads an account's old blob once, uploads it as rows and
  deletes it. `0002` makes the table read-only.
- `0002_rows.neon.sql` — **current**. The row tables, their triggers and RLS.

## Tables

- `library_settings` — one row per user. Holds `progress_reset_at`.
- `puzzles` — position, solutions and metadata. Unique per user on
  `content_key` among live rows, so two devices importing the same file cannot
  both store it.
- `collections` — name and creation time. Unique per user on `name` among live
  rows.
- `collection_puzzles` — one row per puzzle in a collection, with a `position`.
  A puzzle can be in several collections.
- `progress` — one row per puzzle attempted: status, attempts, mistakes, times.
  The recently-seen list used by the random draw is read from
  `last_attempt_at` here rather than stored separately.
- `sessions` — one row per suspended session. The queue and cursor are one
  `jsonb` value, since they only mean something together.

## How a sync works

The client keeps, inside its local library, a copy of the rows as the server
last had them (the *base*) and the highest `revision` it has seen per table.
Each sync:

1. **Pulls** rows with `revision` above that, including deleted ones.
2. **Merges** them into its own rows (`src/model/rows.ts`). A row unchanged
   here since the base takes the server's version. A row changed on both sides
   follows its table's rule: progress takes the higher counts and the latest
   status, a session goes to whichever device played it last, and so on.
3. **Pushes** every row that differs from the base, parents first.

The base is what makes deletion work. A row in the base but gone locally was
deleted here, so it is pushed as a deletion. A row the server marks deleted
goes locally too. The old blob merge had no base, only a union, which is why
deleted things used to come back.

## Rows are marked deleted, never removed

Deleting sets `deleted_at` instead. A device asking for changes can't see a row
that no longer exists, so a real delete would never reach it, and the device
would push the thing back. There is no DELETE grant. Marked rows are kept
indefinitely: even a 1001-puzzle book leaves only a few thousand small rows.
Once a puzzle, collection or membership is marked deleted it stays that way.
Re-importing a deleted puzzle creates a new row with a new id.

## Conflicts are settled on the server too

Two devices can push the same row at once. `BEFORE` triggers apply the same
rules as the client, so the result doesn't depend on which push lands second:
attempts take the max, a deletion only beats attempts made before it, the most
recently played session wins, and the latest reset applies to anything older.
If two devices add the same puzzle or collection name at once, the unique index
turns the second insert into a conflict. The client then pulls again, folds the
two together and retries.

Every write takes a `revision` from one sequence under a per-user advisory
lock. So a user's writes are numbered in commit order, and a device pulling
"above revision N" can never skip a row that commits late.

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

Paste `0001_libraries.neon.sql`, then `0002_rows.neon.sql`, into the Neon SQL
Editor. Doing it in the console rather than over a connection string means no
credential has to be shared with anyone to set this up. Both files can be
re-run safely.

Apply `0002` **right before** deploying the app that uses it. From the moment
it runs, old copies of the app can no longer write their blob and show "Sync
failed" until they reload into the new version. If the Data API doesn't see the
new tables straight away, refresh its schema cache from the Data API page.

### 4. Give the deployed app its base URL

Only the *base* URL is configured. The client derives both the auth service and
the Data API from it by inserting `neonauth` / `apirest` into the hostname, so
there is one value to get right instead of two that must agree:

```bash
gh secret set VITE_NEON_BASE_URL --body "https://<endpoint>.<region>.aws.neon.tech/neondb"
```

Read at build time and inlined into the bundle. That is fine: the endpoint is
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
jars, separate IndexedDB. Device A imports and syncs, device B signs into the
same account and must receive a library it never imported. Then a puzzle
deleted on A must disappear from B and not come back, and a collection deleted
on B must disappear from A. A *third* account must not see any of it. That last
check is the privacy claim, and it is RLS's alone, so it is tested rather than
trusted.

The schema and conflict rules are also covered without a network by
`npm test`. `src/model/rowSync.test.ts` runs the real `0001` and `0002` files in
an in-process Postgres (PGlite) and syncs simulated devices against it,
including races.

Add `--url=https://<user>.github.io/motif/` to run it against the deployed site
instead of a dev server. Do that before believing sync works: the trusted-origin
rule means local success and production success are different facts.

It creates throwaway accounts. Delete them from Neon Console → Auth when done.

## Accounts are created in the app, not the console

Creating a user from the Neon Console provisions an account with no password —
Better Auth only sets one through the sign-up call. Such an account cannot sign
in here, since the app authenticates with email and password. Use **Account →
Create an account** in the app instead.

Absent it, the app builds and runs exactly as before, local-only, with the sync
UI hidden.

## What sync does not do

- **No realtime.** A push happens on a debounce, on backgrounding, and on
  sign-in. Two devices open at once will converge, but not instantly.
- **No sharing.** A library is private to one account by construction; there is
  no policy that would let one user read another's row.
- **No undelete.** A deleted puzzle or collection is gone on every device.
  Re-importing brings it back as a new puzzle with fresh progress.
