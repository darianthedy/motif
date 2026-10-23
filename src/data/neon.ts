import type { createClient } from '@neondatabase/neon-js';
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
