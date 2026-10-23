-- Motif, on Neon's Data API.
--
-- The database is the source of truth. Every edit is a plain write to its row:
-- no merges, no revision numbers, no deletion markers. A device keeps a
-- read-only copy to solve from, and the only thing it writes while offline is
-- attempts and runs, which are inserted and never changed, so two devices can
-- never disagree about one.
--
-- Every row carries the `user_id` of the account it belongs to, defaulted from
-- the JWT, and row-level security keeps each account to its own rows. Foreign
-- keys include `user_id` as well, so a row can only ever point at a row of the
-- same account: a key check bypasses RLS, and would otherwise let one account
-- attach a puzzle to another's collection.
--
-- auth.user_id() returns the JWT subject as text, so user_id is text.
--
-- Apply in the Neon SQL Editor. Safe to re-run.

-- ---------------------------------------------------------------------------
-- Collections
-- ---------------------------------------------------------------------------

-- The id is set by the device that creates the collection, so a new collection
-- and the puzzles imported into it can be written in one go. Names are only a
-- label: two collections may share one, and renaming is an UPDATE.
create table if not exists public.collections (
  id         uuid        primary key,
  user_id    text        not null default auth.user_id(),
  name       text        not null,
  created_at timestamptz not null default now(),
  unique (user_id, id)
);

-- ---------------------------------------------------------------------------
-- Puzzles
-- ---------------------------------------------------------------------------

-- Each puzzle belongs to exactly one collection. The same position in two
-- collections is two puzzles, each with its own progress and comment.
create table if not exists public.puzzles (
  id            uuid             primary key default gen_random_uuid(),
  user_id       text             not null default auth.user_id(),
  collection_id uuid             not null,
  -- Order within the collection.
  position      integer          not null,
  -- Position + solutions (+ placement): what makes two entries the same puzzle.
  content_key   text             not null,
  fen           text             not null,
  solutions     jsonb            not null,   -- Uci[][]
  add_piece     text,                        -- written form, e.g. 'Ng6'
  tags          text[]           not null default '{}',
  comment       text,
  source_id     text,
  rating        double precision,
  added_at      timestamptz      not null default now(),
  unique (user_id, id),
  -- Re-importing a file into the same collection updates its puzzles rather
  -- than adding them twice: the upsert's conflict target.
  unique (collection_id, content_key),
  foreign key (user_id, collection_id)
    references public.collections (user_id, id) on delete cascade
);

-- Marked as needing a look: a wrong solution, a bad position, anything broken.
-- Set in the app only; an import never writes it, so re-importing a file keeps
-- the mark. Added separately so an existing table picks it up on a re-run.
alter table public.puzzles add column if not exists flagged boolean not null default false;

create index if not exists puzzles_collection on public.puzzles (user_id, collection_id);

-- ---------------------------------------------------------------------------
-- Runs
-- ---------------------------------------------------------------------------

-- A run stores only what never changes after it starts. Where it has got to is
-- worked out from its attempts, so two devices playing the same run can never
-- conflict: the worst case is seeing a puzzle twice.
create table if not exists public.runs (
  id         uuid        primary key,
  user_id    text        not null default auth.user_id(),
  -- A collection id, 'all' for the library-wide draw, or 'review'.
  scope      text        not null,
  mode       text        not null
    check (mode in ('ordered', 'randomInCollection', 'randomGlobal', 'reviewMistakes')),
  queue      uuid[]      not null,
  started_at timestamptz not null,
  unique (user_id, id),
  -- One run per scope. Starting a new one replaces it; the device deletes the
  -- older run first and inserts with ON CONFLICT DO NOTHING, so the newer
  -- started_at wins whichever device uploads last.
  unique (user_id, scope)
);

-- ---------------------------------------------------------------------------
-- Attempts
-- ---------------------------------------------------------------------------

-- One row per puzzle played: solved, failed or skipped. Insert-only, with the
-- id generated on the device, so uploading the same attempt twice does nothing
-- (ON CONFLICT DO NOTHING) and the outbox can always retry.
create table if not exists public.attempts (
  id        uuid        primary key,
  user_id   text        not null default auth.user_id(),
  puzzle_id uuid        not null,
  run_id    uuid,
  result    text        not null check (result in ('solved', 'failed', 'skipped')),
  mistakes  integer     not null default 0 check (mistakes >= 0),
  hinted    boolean     not null default false,
  played_at timestamptz not null,
  foreign key (user_id, puzzle_id)
    references public.puzzles (user_id, id) on delete cascade,
  -- Only run_id is cleared: user_id is part of the key but must stay.
  foreign key (user_id, run_id)
    references public.runs (user_id, id) on delete set null (run_id)
);

create index if not exists attempts_puzzle on public.attempts (user_id, puzzle_id);
create index if not exists attempts_run on public.attempts (user_id, run_id);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
-- The whole privacy story: the Data API endpoint is public, and these policies
-- are what keep one account out of another's rows. Nothing for `anonymous`.

do $$
declare
  t text;
begin
  foreach t in array array['collections', 'puzzles', 'runs', 'attempts'] loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists "own rows" on public.%I', t);
    execute format(
      'create policy "own rows" on public.%I for all to authenticated
         using (auth.user_id() = user_id) with check (auth.user_id() = user_id)', t);

    execute format('revoke all on public.%I from authenticated', t);
  end loop;
end;
$$;

-- What each table allows, beyond the policy. Runs and attempts are never
-- updated; a collection only ever changes its name.
grant select, insert, delete on public.collections to authenticated;
grant update (name) on public.collections to authenticated;
grant select, insert, update, delete on public.puzzles to authenticated;
grant select, insert, delete on public.runs to authenticated;
grant select, insert, delete on public.attempts to authenticated;
