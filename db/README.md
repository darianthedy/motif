# Sync backend

One table, one row per user, holding the whole library as JSON. No server code.

Two schema variants are kept here because the app has been pointed at both:

- `0001_libraries.neon.sql` — **current**. Neon's Data API.
- `0001_libraries.supabase.sql` — the original. Kept because it is the same
  design and switching back is a change of client library, not of model.

They differ only in the identity function and grants: Neon exposes
`auth.user_id()` (text, the JWT subject) with predefined `authenticated` and
`anonymous` roles; Supabase has `auth.uid()` (uuid) and grants implicitly.

## Why a blob, and why it is safe

A blob rather than normalized tables, because the client is a blob everywhere
else and a second schema would be a second model to keep in step. What makes a
blob safe to sync is that the client **merges** rather than overwrites — see
`src/model/sync.ts`. Last-write-wins would mean solving ten puzzles on a phone
and losing them the moment a laptop with stale state pushed.

`version` is optimistic concurrency: a writer sends the version its merge was
based on, and the update matches nothing if the row has moved on. The client
re-reads, re-merges and retries. A trigger bumps it, so the client cannot forget.

## Neon setup

### 1. Never put the connection string in the app

This is the one rule. Motif is a **public** static site: anything in the bundle
is readable by anyone. A Postgres connection string is a database owner
credential, so it can only ever live server-side — which a static host does not
have. That is why this uses the Data API and JWTs rather than a direct
connection: the Data API endpoint is meant to be public and RLS does the
enforcing, exactly as an anon key does on Supabase.

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

Paste `0001_libraries.neon.sql` into the Neon SQL Editor. Doing it in the
console rather than over a connection string means no credential has to be
shared with anyone to set this up.

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
same account and must receive a library it never imported, and a *third*
account must not see it at all. That last check is the privacy claim, and it is
RLS's alone, so it is tested rather than trusted.

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
- **No server-side merge.** The merge is client-side and deterministic, so both
  devices compute the same result and whichever writes second stores a superset
  rather than a replacement.
