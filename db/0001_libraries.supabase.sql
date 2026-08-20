-- One row per user: their whole Motif library as a JSON blob.
--
-- A blob rather than normalized tables because the client is a blob everywhere
-- else, and a second schema would be a second model to keep in step. What makes
-- that safe is that the client merges deterministically (see src/model/sync.ts)
-- rather than overwriting: two devices that diverge converge on the same
-- library, so neither needs to win.
create table if not exists public.libraries (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  state      jsonb       not null,
  -- Optimistic concurrency. A writer sends the version it based its merge on;
  -- if the row has moved on since, the update matches nothing and the client
  -- re-reads and re-merges. Without this, two devices saving at once would
  -- still lose whichever landed first.
  version    bigint      not null default 1,
  updated_at timestamptz not null default now()
);

alter table public.libraries enable row level security;

-- A user can see and touch exactly their own row, and nobody else's. This is
-- the whole privacy story: the anon key is public by design, and these policies
-- are what stand between it and someone else's puzzles.
create policy "own library: read"
  on public.libraries for select
  using (auth.uid() = user_id);

create policy "own library: insert"
  on public.libraries for insert
  with check (auth.uid() = user_id);

create policy "own library: update"
  on public.libraries for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "own library: delete"
  on public.libraries for delete
  using (auth.uid() = user_id);

-- Bump version and stamp the time on every write, so the client never has to
-- remember to and a hand-edit in the dashboard cannot desync the counter.
create or replace function public.bump_library_version()
returns trigger
language plpgsql
as $$
begin
  new.version := coalesce(old.version, 0) + 1;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists libraries_bump_version on public.libraries;
create trigger libraries_bump_version
  before update on public.libraries
  for each row execute function public.bump_library_version();
