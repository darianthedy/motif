import { PGlite } from '@electric-sql/pglite';
import v1 from '../../db/0001_libraries.neon.sql?raw';
import v2 from '../../db/0002_rows.neon.sql?raw';
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
  await db.exec(`
    create role authenticated nologin;
    create role anonymous nologin;
    create schema auth;
    grant usage on schema auth to authenticated, anonymous;
    create function auth.user_id() returns text language sql stable
      as $$ select nullif(current_setting('motif.user', true), '') $$;
  `);
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
