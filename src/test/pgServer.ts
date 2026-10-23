import { PGlite } from '@electric-sql/pglite';
import v1 from '../../db/0001_libraries.neon.sql?raw';
import v2 from '../../db/0002_rows.neon.sql?raw';
import schema from '../../db/0001_schema.sql?raw';
import type { Filter, Rest, Row } from '../data/backend';
import { RowConflict } from '../model/rowSync';
import type { Transport, WireRow } from '../model/rowSync';
import type { TableName } from '../model/rows';

/**
 * A real Postgres, in-process, with the production schema applied verbatim.
 *
 * What Neon provides around the schema is stood in for as thinly as possible:
 * an `authenticated` role, and `auth.user_id()` reading the current user from
 * a setting rather than a JWT. Everything else — tables, triggers, policies,
 * grants — is the file that gets pasted into the Neon console, so a test that
 * passes here has exercised the SQL that ships.
 */
export async function startServer(): Promise<PGlite> {
  const db = new PGlite();
  await neonStandIns(db);
  await db.exec(v1);
  await db.exec(v2);
  return db;
}

/** Runs `fn` as the signed-in `userId`, under RLS, in one transaction. */
export async function asUser<T>(
  db: PGlite,
  userId: string,
  fn: (query: <R = WireRow>(sql: string, params?: unknown[]) => Promise<R[]>) => Promise<T>,
): Promise<T> {
  return db.transaction(async (tx) => {
    await tx.query(`select set_config('motif.user', $1, true)`, [userId]);
    await tx.exec('set local role authenticated');
    return fn(async <R>(sql: string, params?: unknown[]) => (await tx.query<R>(sql, params)).rows);
  });
}

export interface Counting {
  pulls: number;
  upserts: number;
}

/**
 * The Data API's behaviour, over SQL.
 *
 * The upsert is the statement PostgREST itself issues for
 * `upsert(rows, { onConflict })`: rows decoded with json_populate_recordset,
 * inserted, and on conflict every sent column overwritten from EXCLUDED — which
 * is what hands the conflict to the BEFORE UPDATE triggers.
 */
export function pgTransport(db: PGlite, userId: string, counting?: Counting): Transport {
  const run = async <T>(fn: Parameters<typeof asUser<T>>[2]) => {
    try {
      return await asUser(db, userId, fn);
    } catch (error) {
      if ((error as { code?: string }).code === '23505') throw new RowConflict();
      throw error;
    }
  };

  return {
    pull: (table: TableName, after: number, limit: number) => {
      if (counting) counting.pulls++;
      return run((q) =>
        q(
          `select * from public.${table} where user_id = $1 and revision > $2
             order by revision limit $3`,
          [userId, after, limit],
        ),
      );
    },

    upsert: (table: TableName, rows: WireRow[], conflict: readonly string[]) => {
      if (counting) counting.upserts++;
      const columns = Object.keys(rows[0]);
      const list = columns.map((c) => `"${c}"`).join(', ');
      const updates = columns
        .filter((c) => !conflict.includes(c))
        .map((c) => `"${c}" = excluded."${c}"`)
        .join(', ');
      return run((q) =>
        q(
          `insert into public.${table} (${list})
             select ${list} from jsonb_populate_recordset(null::public.${table}, $1::jsonb)
           on conflict (${conflict.join(', ')}) do update set ${updates}
           returning *`,
          [JSON.stringify(rows)],
        ),
      );
    },

    fetchLegacy: () =>
      run(async (q) => {
        const rows = await q<{ state: unknown }>(
          'select state from public.libraries where user_id = $1',
          [userId],
        );
        return rows[0]?.state ?? null;
      }),

    deleteLegacy: () =>
      run(async (q) => {
        await q('delete from public.libraries where user_id = $1', [userId]);
      }),
  };
}

// ---------------------------------------------------------------------------
// The current schema
// ---------------------------------------------------------------------------

/** Neon's side of the schema: the role it grants and the identity function. */
async function neonStandIns(db: PGlite) {
  await db.exec(`
    create role authenticated nologin;
    create role anonymous nologin;
    create schema auth;
    grant usage on schema auth to authenticated, anonymous;
    create function auth.user_id() returns text language sql stable
      as $$ select nullif(current_setting('motif.user', true), '') $$;
  `);
}

/** A real Postgres, in-process, with db/0001_schema.sql applied verbatim. */
export async function startDatabase(): Promise<PGlite> {
  const db = new PGlite();
  await neonStandIns(db);
  await db.exec(schema);
  return db;
}

function where(filters: Filter[], params: unknown[]): string {
  if (!filters.length) return '';
  const clauses = filters.map((filter) => {
    if ('eq' in filter) {
      params.push(filter.eq);
      return `"${filter.column}" = $${params.length}`;
    }
    if ('lt' in filter) {
      params.push(filter.lt);
      return `"${filter.column}" < $${params.length}`;
    }
    params.push(JSON.stringify(filter.in));
    return `"${filter.column}"::text in (select jsonb_array_elements_text($${params.length}::jsonb))`;
  });
  return ` where ${clauses.join(' and ')}`;
}

/**
 * PostgREST over SQL, as the signed-in `userId`.
 *
 * Each call is the statement PostgREST itself would issue, and rows come back
 * as JSON, as they do over the wire. An upsert is an INSERT of the columns the
 * rows carry, so the others take their defaults, and on conflict either does
 * nothing or overwrites every sent column.
 */
export function pgRest(db: PGlite, userId: string): Rest {
  const rows = async (sql: string, params: unknown[]) =>
    asUser(db, userId, async (q) => {
      const [result] = await q<{ rows: Row[] }>(sql, params);
      return result.rows;
    });

  return {
    select(table, filters = []) {
      const params: unknown[] = [];
      return rows(
        `select coalesce(jsonb_agg(t), '[]'::jsonb) as rows
           from (select * from public.${table}${where(filters, params)}) t`,
        params,
      );
    },

    insert(table, values, upsert) {
      const columns = Object.keys(values[0]);
      const list = columns.map((c) => `"${c}"`).join(', ');
      let conflict = '';
      if (upsert) {
        const target = upsert.onConflict.map((c) => `"${c}"`).join(', ');
        const updates = columns
          .filter((c) => !upsert.onConflict.includes(c))
          .map((c) => `"${c}" = excluded."${c}"`)
          .join(', ');
        conflict = upsert.ignoreDuplicates
          ? ` on conflict (${target}) do nothing`
          : ` on conflict (${target}) do update set ${updates}`;
      }
      return rows(
        `with stored as (
           insert into public.${table} (${list})
             select ${list} from jsonb_populate_recordset(null::public.${table}, $1::jsonb)
             ${conflict}
           returning *)
         select coalesce(jsonb_agg(stored), '[]'::jsonb) as rows from stored`,
        [JSON.stringify(values)],
      );
    },

    async update(table, patch, filters) {
      const params: unknown[] = [JSON.stringify(patch)];
      const columns = Object.keys(patch);
      const sets = columns
        .map((c) => `"${c}" = (jsonb_populate_record(null::public.${table}, $1::jsonb))."${c}"`)
        .join(', ');
      await asUser(db, userId, (q) =>
        q(`update public.${table} set ${sets}${where(filters, params)}`, params),
      );
    },

    async delete(table, filters) {
      const params: unknown[] = [];
      await asUser(db, userId, (q) =>
        q(`delete from public.${table}${where(filters, params)}`, params),
      );
    },
  };
}
