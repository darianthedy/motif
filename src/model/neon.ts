import { createClient } from '@neondatabase/neon-js';
import { RowConflict } from './rowSync';
import type { Transport, WireRow } from './rowSync';
import type { TableName } from './rows';

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
 * security boundary — see db/0002_rows.neon.sql.
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

interface PostgrestError {
  code?: string;
  message: string;
}

function fail(error: PostgrestError): never {
  // A unique violation is two devices adding the same puzzle or collection at
  // once — a race the sync resolves by pulling and retrying, not a failure.
  if (error.code === '23505') throw new RowConflict();
  throw new Error(error.message);
}

/**
 * Rows over the Data API, scoped to one account.
 *
 * Every query filters on user_id even though RLS already restricts rows to the
 * signed-in user: the filter is what lets Postgres use the (user_id, revision)
 * indexes, and it keeps a query honest if a policy is ever loosened.
 */
export function transportFor(userId: string): Transport {
  if (!client) throw new Error('Sync is not configured');
  const db = client;

  return {
    async pull(table: TableName, after: number, limit: number) {
      const { data, error } = await db
        .from(table)
        .select('*')
        .eq('user_id', userId)
        .gt('revision', after)
        .order('revision', { ascending: true })
        .limit(limit);
      if (error) fail(error);
      return (data ?? []) as WireRow[];
    },

    async upsert(table: TableName, rows: WireRow[], conflict: readonly string[]) {
      const { data, error } = await db
        .from(table)
        .upsert(rows, { onConflict: conflict.join(',') })
        .select('*');
      if (error) fail(error);
      return (data ?? []) as WireRow[];
    },

    async fetchLegacy() {
      const { data, error } = await db
        .from('libraries')
        .select('state')
        .eq('user_id', userId)
        .maybeSingle();
      if (error) fail(error);
      return (data as { state?: unknown } | null)?.state ?? null;
    },

    async deleteLegacy() {
      const { error } = await db.from('libraries').delete().eq('user_id', userId);
      if (error) fail(error);
    },
  };
}
