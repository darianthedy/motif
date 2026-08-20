# Sync backend

One table and Supabase Auth. No Edge Functions, no server code.

This is the opposite arrangement to `battery-monitor`, deliberately. That app
locks its table down entirely and reaches it only through Edge Functions holding
the `service_role` key, because its clients are devices with a shared API key
and no user identity. Motif has a real signed-in user, so the browser talks to
PostgREST directly with the `anon` key and RLS does the enforcing. That is what
the anon key is for, and it is safe in the bundle precisely because every policy
is scoped to `auth.uid()`.

## What is stored

One row per user, holding the entire library as JSON:

```
libraries(user_id uuid pk, state jsonb, version bigint, updated_at timestamptz)
```

A blob rather than normalized tables, because the client is a blob everywhere
else and a second schema would be a second model to keep in step. What makes a
blob safe to sync is that the client **merges** rather than overwrites — see
`src/model/sync.ts`. Last-write-wins would mean solving ten puzzles on a phone
and losing them the moment a laptop with stale state pushed.

`version` is optimistic concurrency: a writer sends the version its merge was
based on, and the update matches nothing if the row has moved on since. The
client then re-reads, re-merges and retries. A database trigger bumps it, so the
client cannot forget and a hand-edit in the dashboard cannot desync it.

## Setup

### 1. Create a project

https://supabase.com → **New project**. Note the **Project URL** and the **anon**
key from Settings → API. The `service_role` key is not needed and must never
reach the client.

### 2. Apply the schema

```bash
npx supabase link --project-ref <your-project-ref>
npx supabase db push
```

Or paste `migrations/0001_libraries.sql` into the SQL Editor.

### 3. Create your account, then close the door

Sign up once from the app's Account screen. Then, in
**Authentication → Sign In / Providers → Email**, turn **"Allow new users to
sign up"** off.

This matters more than it looks. The anon key is public, so without this anyone
who reads the bundle can create an account on the project. They still cannot see
your puzzles — RLS guarantees that — but they can consume the free-tier quota.
Disabling signup after creating your account closes it.

Consider also turning **"Confirm email"** on, or off if you would rather not
deal with deliverability for a single-user project.

### 4. Give the deployed app its keys

```bash
gh secret set VITE_SUPABASE_URL      --body "https://<project-ref>.supabase.co"
gh secret set VITE_SUPABASE_ANON_KEY --body "<anon-key>"
```

They are read at build time by the deploy workflow and inlined into the bundle.
They live in repo secrets rather than the tree only so the key is not scraped
off a public repo and spent against the quota — this is hygiene, not a security
boundary. RLS is the security boundary.

For local development, copy `.env.example` to `.env` and fill it in.

Absent both variables the app builds and runs exactly as before, local-only,
with the sync UI hidden.

## What sync does not do

- **No realtime.** A push happens on a debounce, on backgrounding, and on
  sign-in. Two devices open at once will converge, but not instantly.
- **No sharing.** A library is private to one account by construction; there is
  no policy that would let one user read another's row.
- **No server-side merge.** The merge is client-side and deterministic, so both
  devices compute the same result and whichever writes second stores a superset
  rather than a replacement.
