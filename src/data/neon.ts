import { createClient } from '@neondatabase/neon-js';
import type { Account, User } from './account';
import { restBackend } from './backend';
import type { Filter, Rest, Row } from './backend';

type Client = ReturnType<typeof createClient>;

/** Rows per request when reading; well under any server-side cap. */
const PAGE_SIZE = 1000;

interface Filterable<T> {
  eq(column: string, value: unknown): T;
  in(column: string, values: readonly unknown[]): T;
  lt(column: string, value: unknown): T;
}

function filtered<T extends Filterable<T>>(query: T, filters: Filter[]): T {
  for (const filter of filters) {
    if ('eq' in filter) query = query.eq(filter.column, filter.eq);
    else if ('lt' in filter) query = query.lt(filter.column, filter.lt);
    else query = query.in(filter.column, filter.in);
  }
  return query;
}

function check({ error }: { error: { message: string } | null }) {
  if (error) throw new Error(error.message);
}

/**
 * Neon's Data API as the backend's `Rest`.
 *
 * Nothing secret is involved: the Data API endpoint is public by design, and
 * the signed-in account's JWT plus row-level security decide what it can see.
 */
export function neonRest(client: Client): Rest {
  return {
    async select(table, filters = []) {
      const all: Row[] = [];
      for (let from = 0; ; from += PAGE_SIZE) {
        const result = await filtered(client.from(table).select('*'), filters)
          .order('id')
          .range(from, from + PAGE_SIZE - 1);
        check(result);
        const page = (result.data ?? []) as Row[];
        all.push(...page);
        if (page.length < PAGE_SIZE) return all;
      }
    },

    async insert(table, rows, upsert) {
      const query = upsert
        ? client.from(table).upsert(rows, {
            onConflict: upsert.onConflict.join(','),
            ignoreDuplicates: upsert.ignoreDuplicates ?? false,
            // A column the rows leave out takes its default, not null: that
            // is how a new puzzle gets its id.
            defaultToNull: false,
          })
        : client.from(table).insert(rows, { defaultToNull: false });
      const result = await query.select('*');
      check(result);
      return (result.data ?? []) as Row[];
    },

    async update(table, patch, filters) {
      check(await filtered(client.from(table).update(patch), filters));
    },

    async delete(table, filters) {
      check(await filtered(client.from(table).delete(), filters));
    },
  };
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

function failed(result: unknown): string | null {
  const error = (result as { error?: { message?: string } | null })?.error;
  return error ? (error.message ?? 'Authentication failed') : null;
}

/**
 * Signing in with Neon Auth, and the Data API as the signed-in account.
 *
 * Only the base URL is configured. The client derives both the auth service
 * and the Data API from it by inserting `neonauth` / `apirest` into the
 * hostname, so there is one value to get right instead of two that must agree.
 */
export function neonAccount(baseUrl: string): Account {
  const client = createClient(baseUrl);

  return {
    async currentUser(): Promise<User | null> {
      const session = (await client.auth.getSession()) as SessionEnvelope;
      const user = session?.data?.user;
      return user?.id ? { id: user.id, email: user.email ?? '' } : null;
    },

    async signIn(email, password) {
      const message = failed(await client.auth.signIn.email({ email, password }));
      if (message) throw new Error(message);
    },

    async signUp(email, password) {
      // Better Auth requires a name; the app has no use for one, so the local
      // part of the address stands in rather than asking for a field nobody reads.
      const message = failed(
        await client.auth.signUp.email({ email, password, name: email.split('@')[0] }),
      );
      if (message) throw new Error(message);
    },

    async signOut() {
      await client.auth.signOut();
    },

    backend(user) {
      return restBackend(neonRest(client), user.id);
    },
  };
}
