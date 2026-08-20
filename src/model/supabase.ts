import { createClient } from '@supabase/supabase-js';
import type { Session, SupabaseClient, User } from '@supabase/supabase-js';
import { mergeStates } from './sync';
import { parseState } from './storage';
import type { AppState } from './state';

/**
 * Cross-device sync, optional.
 *
 * The app is offline-first and works with no backend at all: IndexedDB remains
 * the source of truth for the running session, and sync is a background
 * reconciliation on top. If the two environment variables are absent — a fork,
 * a local build, someone's checkout — `syncAvailable` is false, no client is
 * constructed, and every screen behaves exactly as it did before.
 *
 * The anon key is public by design and ships in the bundle. It is safe there
 * only because every policy on `libraries` is scoped to `auth.uid()`; see
 * supabase/migrations/0001_libraries.sql. The service_role key must never
 * appear in this file or anywhere else in the client.
 */
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const syncAvailable = Boolean(url && anonKey);

export const supabase: SupabaseClient | null = syncAvailable
  ? createClient(url!, anonKey!, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        // The app is served from a static host with no routing, so there is no
        // callback route to parse a magic-link fragment on. Detecting it in the
        // page we land on is exactly right here.
        detectSessionInUrl: true,
      },
    })
  : null;

export interface RemoteLibrary {
  state: AppState;
  version: number;
}

/** The signed-in user, or null when signed out or unconfigured. */
export async function currentUser(): Promise<User | null> {
  if (!supabase) return null;
  const { data } = await supabase.auth.getUser();
  return data.user ?? null;
}

export function onAuthChange(fn: (session: Session | null) => void): () => void {
  if (!supabase) return () => {};
  const { data } = supabase.auth.onAuthStateChange((_event, session) => fn(session));
  return () => data.subscription.unsubscribe();
}

export async function signInWithPassword(email: string, password: string) {
  if (!supabase) throw new Error('Sync is not configured');
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
}

export async function signUp(email: string, password: string) {
  if (!supabase) throw new Error('Sync is not configured');
  const { error } = await supabase.auth.signUp({ email, password });
  if (error) throw error;
}

export async function signOut() {
  await supabase?.auth.signOut();
}

/** Reads the stored library, or null when the user has never pushed one. */
export async function fetchRemote(userId: string): Promise<RemoteLibrary | null> {
  if (!supabase) return null;
  const { data, error } = await supabase
    .from('libraries')
    .select('state, version')
    .eq('user_id', userId)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;
  // Parsed rather than trusted: the row is JSON that may predate a schema
  // change or have been hand-edited in the dashboard, and the same leniency
  // that protects the local store should protect this.
  return { state: parseState(data.state), version: data.version as number };
}

export class SyncConflict extends Error {
  constructor() {
    super('The remote library changed while syncing');
    this.name = 'SyncConflict';
  }
}

/**
 * Pushes a merged library, refusing to overwrite a newer one.
 *
 * `expectedVersion` is the version the merge was based on. If the row has moved
 * on, the update matches no rows and this throws `SyncConflict` — the caller
 * re-reads and re-merges rather than clobbering. Passing null means "there was
 * no row when I looked", which becomes an insert.
 */
export async function pushRemote(
  userId: string,
  state: AppState,
  expectedVersion: number | null,
): Promise<number> {
  if (!supabase) throw new Error('Sync is not configured');

  if (expectedVersion === null) {
    const { data, error } = await supabase
      .from('libraries')
      .insert({ user_id: userId, state })
      .select('version')
      .single();
    // A concurrent insert from another device trips the primary key; that is a
    // conflict, not a failure, and resolves on the next round.
    if (error) throw error.code === '23505' ? new SyncConflict() : error;
    return data.version as number;
  }

  const { data, error } = await supabase
    .from('libraries')
    .update({ state })
    .eq('user_id', userId)
    .eq('version', expectedVersion)
    .select('version')
    .maybeSingle();

  if (error) throw error;
  if (!data) throw new SyncConflict();
  return data.version as number;
}

/**
 * One full reconciliation: read, merge, write, retrying on conflict.
 *
 * Returns the merged library so the caller can adopt it locally. Both sides
 * compute the same merge, so whichever device writes second still ends up
 * storing a superset rather than a replacement.
 */
export async function syncOnce(
  userId: string,
  local: AppState,
  attempts = 3,
): Promise<{ state: AppState; version: number }> {
  let lastError: unknown;

  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const remote = await fetchRemote(userId);
      const merged = remote ? mergeStates(local, remote.state) : local;
      const version = await pushRemote(userId, merged, remote?.version ?? null);
      return { state: merged, version };
    } catch (error) {
      if (!(error instanceof SyncConflict)) throw error;
      lastError = error;
      // Someone else wrote between our read and our write. Loop: the next read
      // sees their version and merges on top of it.
    }
  }

  throw lastError ?? new Error('Sync failed');
}
