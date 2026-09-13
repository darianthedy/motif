-- Motif sync, one row per thing.
--
-- Replaces the single-blob design of 0001 (one `libraries` row per user holding
-- the whole library as JSON). Every puzzle, collection, collection membership,
-- progress entry and suspended session is now its own row, tied to the account
-- by `user_id`, so a sync moves only what changed.
--
-- Three rules hold for every table here:
--
-- 1. Rows are never deleted, only marked: `deleted_at` is set instead. A device
--    that asks "what changed since I last looked?" cannot see a row that no
--    longer exists, so a hard delete would never reach it — and a device that
--    never hears about a deletion hands the thing straight back on its next
--    push. The marked row is what carries the deletion. There is deliberately
--    no DELETE grant.
--
-- 2. Every write takes a fresh `revision` from one sequence. A device keeps the
--    highest revision it has seen per table and asks only for rows above it.
--    Writes are serialized per user (see motif_stamp), so for any one user
--    revision order is commit order and a reader can never skip a row.
--
-- 3. Conflicts are resolved here, in BEFORE triggers, not only on the client.
--    Two devices can push the same row at once; the trigger makes the result
--    the same whichever lands second, so neither loses a solve.
--
-- Apply after 0001, in the Neon SQL Editor. The `libraries` table stays until
-- every device has migrated — the client reads it once, uploads its contents as
-- rows and deletes the user's blob — but it becomes read-only below, so an old
-- cached copy of the app cannot keep writing into it.

-- ---------------------------------------------------------------------------
-- Shared machinery
-- ---------------------------------------------------------------------------

create sequence if not exists public.motif_revision;
grant usage on sequence public.motif_revision to authenticated;

-- Stamps every write with the next revision.
--
-- The advisory lock is what makes an incremental pull safe. Without it, a write
-- that takes revision 10 can commit after one that took revision 11; a device
-- that pulled in between has already moved its cursor past 10 and never sees
-- that row. Holding a per-user lock until commit means a user's writes take
-- revisions in the order they commit. Other users are unaffected: they hash to
-- other locks, and every read filters by user anyway.
create or replace function public.motif_stamp()
returns trigger
language plpgsql
as $$
begin
  perform pg_advisory_xact_lock(hashtext(new.user_id));
  new.revision := nextval('public.motif_revision');
  new.updated_at := now();
  return new;
end;
$$;

-- For rows whose deletion is final: puzzles, collections and memberships.
--
-- A deleted row stays deleted whatever is pushed over it. The client never
-- revives one on purpose — re-importing a deleted puzzle creates a new id — so
-- a live push onto a marked row can only be a device that has not heard about
-- the deletion yet. Returning OLD (rather than NULL) still performs the write,
-- so the pushing device gets the deletion back in the response.
create or replace function public.motif_keep_deleted()
returns trigger
language plpgsql
as $$
begin
  if old.deleted_at is not null then
    return old;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Settings: one row per user
-- ---------------------------------------------------------------------------

create table if not exists public.library_settings (
  user_id           text        primary key default auth.user_id(),
  -- When the user last asked for a clean slate. Any progress or session older
  -- than this was discarded on purpose; see motif_merge_progress.
  progress_reset_at bigint,
  revision          bigint      not null default 0,
  updated_at        timestamptz not null default now()
);

create or replace function public.motif_merge_settings()
returns trigger
language plpgsql
as $$
begin
  -- A reset is a fact about the past, so the later one wins whichever device
  -- pushes last.
  if old.progress_reset_at is not null then
    new.progress_reset_at := greatest(old.progress_reset_at, new.progress_reset_at);
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Puzzles
-- ---------------------------------------------------------------------------

create table if not exists public.puzzles (
  user_id     text        not null default auth.user_id(),
  id          text        not null,
  -- Position + setup move + solutions (+ placement): the puzzle's identity.
  -- Two devices importing the same file generate different ids for the same
  -- puzzle; this is how they find each other.
  content_key text        not null,
  fen         text        not null,
  setup_move  text,
  solutions   jsonb       not null,   -- Uci[][]
  add_piece   jsonb,                  -- { color, type, square }
  tags        text[]      not null default '{}',
  comment     text,
  source_id   text,
  rating      double precision,
  added_at    bigint      not null,   -- ms since epoch, as the app keeps it
  deleted_at  bigint,                 -- ms since epoch; null while it exists
  revision    bigint      not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (user_id, id)
);

-- Only among puzzles that still exist: a deleted puzzle re-imported later gets
-- a new row rather than colliding with its own marker.
create unique index if not exists puzzles_live_content
  on public.puzzles (user_id, content_key) where deleted_at is null;
create index if not exists puzzles_revision on public.puzzles (user_id, revision);

-- ---------------------------------------------------------------------------
-- Collections and membership
-- ---------------------------------------------------------------------------

create table if not exists public.collections (
  user_id    text        not null default auth.user_id(),
  id         text        not null,
  name       text        not null,
  created_at bigint      not null,
  deleted_at bigint,
  revision   bigint      not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

-- Name is how imports on two devices agree on a collection without sharing
-- ids, so two live collections may not share one.
create unique index if not exists collections_live_name
  on public.collections (user_id, name) where deleted_at is null;
create index if not exists collections_revision on public.collections (user_id, revision);

-- One row per puzzle in a collection. A puzzle may be in several collections.
create table if not exists public.collection_puzzles (
  user_id       text             not null default auth.user_id(),
  collection_id text             not null,
  puzzle_id     text             not null,
  -- Order within the collection. Only ever appended to, so two devices adding
  -- at once may tie; readers break ties by puzzle_id.
  position      double precision not null,
  deleted_at    bigint,
  revision      bigint           not null default 0,
  updated_at    timestamptz      not null default now(),
  primary key (user_id, collection_id, puzzle_id),
  foreign key (user_id, collection_id) references public.collections (user_id, id),
  foreign key (user_id, puzzle_id) references public.puzzles (user_id, id)
);

create index if not exists collection_puzzles_revision
  on public.collection_puzzles (user_id, revision);
create index if not exists collection_puzzles_puzzle
  on public.collection_puzzles (user_id, puzzle_id);

-- ---------------------------------------------------------------------------
-- Progress
-- ---------------------------------------------------------------------------

create table if not exists public.progress (
  user_id         text        not null default auth.user_id(),
  puzzle_id       text        not null,
  status          text        not null check (status in ('unseen', 'solved', 'failed')),
  attempts        integer     not null default 0,
  mistakes        integer     not null default 0,
  last_attempt_at bigint,
  first_solved_at bigint,
  deleted_at      bigint,
  revision        bigint      not null default 0,
  updated_at      timestamptz not null default now(),
  primary key (user_id, puzzle_id),
  foreign key (user_id, puzzle_id) references public.puzzles (user_id, id)
);

create index if not exists progress_revision on public.progress (user_id, revision);

-- Two devices solving the same puzzle must both be counted.
--
-- Counters take the max rather than the sum: both devices count up from the
-- same shared value, so a sum would count every attempt they both knew about
-- twice. Status follows the most recent attempt. A deletion — a reset, or the
-- puzzle being deleted — only wins over attempts made before it.
create or replace function public.motif_merge_progress()
returns trigger
language plpgsql
as $$
declare
  reset_at bigint;
begin
  if tg_op = 'UPDATE' then
    if new.deleted_at is not null then
      if old.deleted_at is null and coalesce(old.last_attempt_at, 0) > new.deleted_at then
        return old;
      end if;
    elsif old.deleted_at is not null then
      if coalesce(new.last_attempt_at, 0) <= old.deleted_at then
        return old;
      end if;
      -- An attempt after the deletion starts afresh, as it did on the device.
    else
      new.status := case
        when coalesce(new.last_attempt_at, 0) >= coalesce(old.last_attempt_at, 0)
          then new.status
        else old.status
      end;
      new.attempts := greatest(old.attempts, new.attempts);
      new.mistakes := greatest(old.mistakes, new.mistakes);
      new.last_attempt_at := greatest(old.last_attempt_at, new.last_attempt_at);
      new.first_solved_at := least(old.first_solved_at, new.first_solved_at);
    end if;
  end if;

  -- An attempt older than the latest reset was discarded on purpose. Checked
  -- here as well as on the device, because a device that has not heard about
  -- the reset yet can still push one.
  if new.deleted_at is null then
    select s.progress_reset_at into reset_at
      from public.library_settings s where s.user_id = new.user_id;
    if reset_at is not null and coalesce(new.last_attempt_at, 0) < reset_at then
      new.deleted_at := reset_at;
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Sessions
-- ---------------------------------------------------------------------------

-- One row per suspended session, keyed as the app keys them: a collection id,
-- '*' for the library-wide draw, or 'review'. The queue and cursor are only
-- meaningful together, so the session itself is one jsonb value rather than
-- being split into columns.
create table if not exists public.sessions (
  user_id        text        not null default auth.user_id(),
  key            text        not null,
  session        jsonb       not null,
  last_active_at bigint      not null,
  deleted_at     bigint,
  revision       bigint      not null default 0,
  updated_at     timestamptz not null default now(),
  primary key (user_id, key)
);

create index if not exists sessions_revision on public.sessions (user_id, revision);

-- The most recent event wins outright: a session played on or a session
-- finished. Interleaving two queues would produce a position neither device
-- was ever in.
create or replace function public.motif_merge_session()
returns trigger
language plpgsql
as $$
declare
  reset_at bigint;
begin
  if tg_op = 'UPDATE'
     and coalesce(old.deleted_at, old.last_active_at)
       > coalesce(new.deleted_at, new.last_active_at) then
    return old;
  end if;

  if new.deleted_at is null then
    select s.progress_reset_at into reset_at
      from public.library_settings s where s.user_id = new.user_id;
    if reset_at is not null and new.last_active_at < reset_at then
      new.deleted_at := reset_at;
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
-- BEFORE triggers fire in name order, so the merge runs first and the stamp
-- sees its result.

drop trigger if exists motif_10_merge on public.library_settings;
create trigger motif_10_merge before update on public.library_settings
  for each row execute function public.motif_merge_settings();

drop trigger if exists motif_10_merge on public.puzzles;
create trigger motif_10_merge before update on public.puzzles
  for each row execute function public.motif_keep_deleted();

drop trigger if exists motif_10_merge on public.collections;
create trigger motif_10_merge before update on public.collections
  for each row execute function public.motif_keep_deleted();

drop trigger if exists motif_10_merge on public.collection_puzzles;
create trigger motif_10_merge before update on public.collection_puzzles
  for each row execute function public.motif_keep_deleted();

drop trigger if exists motif_10_merge on public.progress;
create trigger motif_10_merge before insert or update on public.progress
  for each row execute function public.motif_merge_progress();

drop trigger if exists motif_10_merge on public.sessions;
create trigger motif_10_merge before insert or update on public.sessions
  for each row execute function public.motif_merge_session();

do $$
declare
  t text;
begin
  foreach t in array array[
    'library_settings', 'puzzles', 'collections', 'collection_puzzles', 'progress', 'sessions'
  ] loop
    execute format('drop trigger if exists motif_90_stamp on public.%I', t);
    execute format(
      'create trigger motif_90_stamp before insert or update on public.%I
         for each row execute function public.motif_stamp()', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
-- The whole privacy story, as in 0001: the Data API endpoint is public and
-- these policies are what keep one account out of another's rows. No policy
-- for `anonymous`, and no DELETE: rows are marked, never removed.

do $$
declare
  t text;
begin
  foreach t in array array[
    'library_settings', 'puzzles', 'collections', 'collection_puzzles', 'progress', 'sessions'
  ] loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists "own rows: read" on public.%I', t);
    execute format(
      'create policy "own rows: read" on public.%I for select to authenticated
         using (auth.user_id() = user_id)', t);

    execute format('drop policy if exists "own rows: insert" on public.%I', t);
    execute format(
      'create policy "own rows: insert" on public.%I for insert to authenticated
         with check (auth.user_id() = user_id)', t);

    execute format('drop policy if exists "own rows: update" on public.%I', t);
    execute format(
      'create policy "own rows: update" on public.%I for update to authenticated
         using (auth.user_id() = user_id) with check (auth.user_id() = user_id)', t);

    execute format('grant select, insert, update on public.%I to authenticated', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Retire the blob
-- ---------------------------------------------------------------------------
-- Read and delete only. An old cached copy of the app that tries to push its
-- blob now fails instead of quietly writing a library nobody reads, and the
-- failure is what prompts its reload into the new version.

drop policy if exists "own library: insert" on public.libraries;
drop policy if exists "own library: update" on public.libraries;
revoke insert, update on public.libraries from authenticated;
