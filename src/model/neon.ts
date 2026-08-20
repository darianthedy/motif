import { createClient } from '@neondatabase/neon-js';
import { mergeStates } from './sync';
import { parseState } from './storage';
import type { AppState } from './state';

/**
 * Cross-device sync on Neon's Data API, optional.
 *
 * The app is offline-first and works with no backend at all: IndexedDB remains
 * the source of truth for the running session, and sync is a background
 * reconciliation on top. With `VITE_NEON_BASE_URL` unset — a fork, a local
 * build, someone's checkout — `syncAvailable` is false, no client is
 * constructed, and every screen behaves exactly as it did before.
 *
 * Only the *base* URL is configured. The library derives both the auth service
 * and the Data API from it by inserting `neonauth` / `apirest` into the
 * hostname, so there is one value to get right instead of two that must agree.
 *
 * Nothing secret lives here. A Postgres connection string could never appear in
 * this file: the app is a public static site, so anything in the bundle is
 * readable by anyone. The Data API endpoint is public by design and RLS is the
 * security boundary — see db/0001_libraries.neon.sql.
 */
const baseUrl = import.meta.env.VITE_NEON_BASE_URL as string | undefined;

export const syncAvailable = Boolean(baseUrl);

const client = syncAvailable ? createClient(baseUrl!) : null;

export interface SyncUser {
  id: string;
  email: string;
}

/**
 * Better Auth's session shape, narrowed to what is actually used.
 *
 * Typed structurally rather than imported: the package is beta, and depending
 * on its exact response type would make an upstream rename a build break for a
 * field this file barely touches.
 */
interface SessionEnvelope {
  data?: { user?: { id?: string; email?: string } | null } | null;
}

export async function currentUser(): Promise<SyncUser | null> {
  if (!client) return null;
  try {
    const session = (await client.auth.getSession()) as SessionEnvelope;
    const user = session?.data?.user;
    return user?.id ? { id: user.id, email: user.email ?? '' } : null;
  } catch {
    // A missing or expired session is the ordinary signed-out case, not an
    // error worth surfacing.
    return null;
  }
}

function failed(result: unknown): string | null {
  const error = (result as { error?: { message?: string } | null })?.error;
  return error ? (error.message ?? 'Authentication failed') : null;
}

export async function signInWithPassword(email: string, password: string) {
  if (!client) throw new Error('Sync is not configured');
  const message = failed(await client.auth.signIn.email({ email, password }));
  if (message) throw new Error(message);
}

export async function signUp(email: string, password: string) {
  if (!client) throw new Error('Sync is not configured');
  // Better Auth requires a name; the app has no use for one, so the local part
  // of the address stands in rather than asking for a field nobody reads.
  const message = failed(
    await client.auth.signUp.email({ email, password, name: email.split('@')[0] }),
  );
  if (message) throw new Error(message);
}

export async function signOut() {
  await client?.auth.signOut();
}

export interface RemoteLibrary {
  state: AppState;
  version: number;
}

/** Reads the stored library, or null when the user has never pushed one. */
export async function fetchRemote(userId: string): Promise<RemoteLibrary | null> {
  if (!client) return null;
  const { data, error } = await client
    .from('libraries')
    .select('state, version')
    .eq('user_id', userId)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) return null;
  // Parsed rather than trusted: the row is JSON that may predate a schema
  // change or have been hand-edited in the console, and the same leniency that
  // protects the local store should protect this.
  return { state: parseState(data.state), version: Number(data.version) };
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
 * re-reads and re-merges rather than clobbering. Null means "there was no row
 * when I looked", which becomes an insert.
 */
export async function pushRemote(
  userId: string,
  state: AppState,
  expectedVersion: number | null,
): Promise<number> {
  if (!client) throw new Error('Sync is not configured');

  if (expectedVersion === null) {
    const { data, error } = await client
      .from('libraries')
      .insert({ user_id: userId, state })
      .select('version')
      .single();
    // A concurrent insert from another device trips the primary key; that is a
    // conflict, not a failure, and resolves on the next round.
    if (error) throw error.code === '23505' ? new SyncConflict() : new Error(error.message);
    return Number(data.version);
  }

  const { data, error } = await client
    .from('libraries')
    .update({ state })
    .eq('user_id', userId)
    .eq('version', expectedVersion)
    .select('version')
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) throw new SyncConflict();
  return Number(data.version);
}

/**
 * One full reconciliation: read, merge, write, retrying on conflict.
 *
 * Returns the merged library so the caller can adopt it. Both devices compute
 * the same merge, so whichever writes second still stores a superset rather
 * than a replacement.
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
