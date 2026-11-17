-- Motif: Scan Training.
--
-- Scan puzzles are kept apart from puzzles. A scan puzzle carries the position
-- before the opponent's move, that move, and a graded answer for each step,
-- which `puzzles` has no place for. The puzzle maker (Caïssa) works out every
-- answer; Motif only checks, stores and compares. See
-- "Motif - iOS Scan Training Plan.md" §2 and §3.
--
-- The same model as the Puzzles tab, minus collections: one pool of puzzles,
-- runs that store only their fixed queue, and attempts that are only ever
-- inserted. Progress and where a run has got to are worked out on the device.
--
-- The same rules as 0001_schema.sql: every row carries its account's
-- `user_id`, row-level security keeps each account to its own rows, and
-- foreign keys include `user_id`.
--
-- Apply in the Neon SQL Editor, after 0001_schema.sql. Safe to re-run.

-- ---------------------------------------------------------------------------
-- Scan puzzles
-- ---------------------------------------------------------------------------

create table if not exists public.scan_puzzles (
  id          uuid        primary key default gen_random_uuid(),
  user_id     text        not null default auth.user_id(),
  -- fen_before (first four fields) + last_move: the same position sent twice
  -- updates the row instead of adding a second one.
  content_key text        not null,
  fen_before  text        not null,   -- before the opponent's last move
  last_move   text        not null,   -- UCI
  answer      jsonb       not null,   -- ScanAnswer: flagged, quickScan, moves, ...
  version     integer     not null,   -- format version
  -- The maker's own labels: 'own game', 'lichess', ...
  source      text,
  source_id   text,
  added_at    timestamptz not null default now(),
  unique (user_id, id),
  -- The upsert's conflict target, for imports and for direct writes.
  unique (user_id, content_key)
);

-- ---------------------------------------------------------------------------
-- Scan runs
-- ---------------------------------------------------------------------------

-- As `runs`: only what never changes after a run starts.
create table if not exists public.scan_runs (
  id         uuid        primary key,
  user_id    text        not null default auth.user_id(),
  -- 'all' for the whole pool, or 'review'.
  scope      text        not null check (scope in ('all', 'review')),
  mode       text        not null check (mode in ('randomGlobal', 'reviewMistakes')),
  queue      uuid[]      not null,
  started_at timestamptz not null,
  unique (user_id, id),
  -- One run per scope, as for puzzles.
  unique (user_id, scope)
);

-- ---------------------------------------------------------------------------
-- Scan attempts
-- ---------------------------------------------------------------------------

-- As `attempts`: insert-only, id made on the device, so the outbox can always
-- retry and uploading twice stores once.
create table if not exists public.scan_attempts (
  id         uuid        primary key,
  user_id    text        not null default auth.user_id(),
  puzzle_id  uuid        not null,
  run_id     uuid,
  result     text        not null check (result in ('solved', 'failed', 'skipped')),
  flag_call  boolean,                  -- null for a skip
  -- Per step: ms taken, limit in force, missed and extra squares, the move.
  detail     jsonb       not null,
  played_at  timestamptz not null,
  foreign key (user_id, puzzle_id)
    references public.scan_puzzles (user_id, id) on delete cascade,
  foreign key (user_id, run_id)
    references public.scan_runs (user_id, id) on delete set null (run_id)
);

create index if not exists scan_attempts_puzzle on public.scan_attempts (user_id, puzzle_id);
create index if not exists scan_attempts_run on public.scan_attempts (user_id, run_id);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['scan_puzzles', 'scan_runs', 'scan_attempts'] loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists "own rows" on public.%I', t);
    execute format(
      'create policy "own rows" on public.%I for all to authenticated
         using (auth.user_id() = user_id) with check (auth.user_id() = user_id)', t);

    execute format('revoke all on public.%I from authenticated', t);
  end loop;
end;
$$;

-- A re-sent puzzle updates its answer and labels. Runs and attempts are never
-- updated. `content_key` is in the list because PostgREST's upsert (the app's
-- import and the maker's direct writes) sets every column it sends, the
-- conflict key included, to the value it already has.
grant select, insert, delete on public.scan_puzzles to authenticated;
grant update (content_key, fen_before, last_move, answer, version, source, source_id)
  on public.scan_puzzles to authenticated;
grant select, insert, delete on public.scan_runs to authenticated;
grant select, insert, delete on public.scan_attempts to authenticated;
