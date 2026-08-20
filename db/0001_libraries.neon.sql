-- Motif sync, on Neon's Data API.
--
-- Same shape as the Supabase variant (db/0001_libraries.supabase.sql): one row
-- per user holding the whole library as JSON, with a version for optimistic
-- concurrency. What differs is only the identity function and the grants —
-- Neon's Data API exposes auth.user_id() from the JWT and ships predefined
-- `authenticated` and `anonymous` roles, where Supabase has auth.uid().
--
-- auth.user_id() returns the JWT subject as text, so user_id is text here
-- rather than uuid.

create table if not exists public.libraries (
  user_id    text        primary key,
  state      jsonb       not null,
  -- A writer sends the version its merge was based on; if the row moved on,
  -- the update matches nothing and the client re-reads and re-merges. Without
  -- this, two devices saving at once still lose whichever landed first.
  version    bigint      not null default 1,
  updated_at timestamptz not null default now()
);

alter table public.libraries enable row level security;

-- The whole privacy story. The Data API endpoint is public by design; these
-- policies are what stand between it and someone else's puzzles. Note there is
-- deliberately no policy for the `anonymous` role: signed out means no access,
-- not read-only access.
create policy "own library: read"
  on public.libraries for select
  to authenticated
  using (auth.user_id() = user_id);

create policy "own library: insert"
  on public.libraries for insert
  to authenticated
  with check (auth.user_id() = user_id);

create policy "own library: update"
  on public.libraries for update
  to authenticated
  using (auth.user_id() = user_id)
  with check (auth.user_id() = user_id);

create policy "own library: delete"
  on public.libraries for delete
  to authenticated
  using (auth.user_id() = user_id);

-- RLS restricts which rows a role may touch; it does not grant the privilege to
-- touch the table at all. Both are needed.
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.libraries to authenticated;

-- Bump version and stamp the time on every write, so the client never has to
-- remember to and a hand-edit in the console cannot desync the counter.
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
