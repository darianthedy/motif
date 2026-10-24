-- Motif: game collections.
--
-- Games are kept apart from puzzles. A game is read, not solved: it has no
-- runs and no attempts, so it needs none of their tables, and the puzzle
-- tables need not know it exists.
--
-- The same rules as 0001_schema.sql: every row carries its account's
-- `user_id`, row-level security keeps each account to its own rows, and
-- foreign keys include `user_id` so a game can only be in a collection of
-- the same account.
--
-- Apply in the Neon SQL Editor, after 0001_schema.sql. Safe to re-run.

-- ---------------------------------------------------------------------------
-- Game collections
-- ---------------------------------------------------------------------------

create table if not exists public.game_collections (
  id         uuid        primary key,
  user_id    text        not null default auth.user_id(),
  name       text        not null,
  created_at timestamptz not null default now(),
  unique (user_id, id)
);

-- ---------------------------------------------------------------------------
-- Games
-- ---------------------------------------------------------------------------

-- The PGN text is the game: headers, moves, comments and variations together.
-- The device reads it into a tree and writes the whole text back on an edit,
-- so there is nothing to keep in step. No dedupe key: a game is not solved,
-- so the same one twice has no progress to merge.
create table if not exists public.games (
  id            uuid        primary key,
  user_id       text        not null default auth.user_id(),
  collection_id uuid        not null,
  -- Order within the collection.
  position      integer     not null,
  pgn           text        not null,
  -- Which side is at the bottom of the board.
  orientation   text        not null default 'w' check (orientation in ('w', 'b')),
  added_at      timestamptz not null default now(),
  unique (user_id, id),
  foreign key (user_id, collection_id)
    references public.game_collections (user_id, id) on delete cascade
);

create index if not exists games_collection on public.games (user_id, collection_id);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['game_collections', 'games'] loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists "own rows" on public.%I', t);
    execute format(
      'create policy "own rows" on public.%I for all to authenticated
         using (auth.user_id() = user_id) with check (auth.user_id() = user_id)', t);

    execute format('revoke all on public.%I from authenticated', t);
  end loop;
end;
$$;

-- A collection only ever changes its name. A game changes its text, its
-- board's orientation, and where it is.
grant select, insert, delete on public.game_collections to authenticated;
grant update (name) on public.game_collections to authenticated;
grant select, insert, delete on public.games to authenticated;
grant update (collection_id, position, pgn, orientation) on public.games to authenticated;
