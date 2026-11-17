import type { PGlite } from '@electric-sql/pglite';
import { beforeAll, describe, expect, it } from 'vitest';
import { asUser, startDatabase } from '../test/pgServer';

/**
 * db/0003_scan.sql, checked at the SQL level. Scan Training is iOS only, so
 * the web Backend has no scan methods; these talk to the tables directly, the
 * way the iOS app and the puzzle maker's direct writes do.
 */

let db: PGlite;
let account = 0;
const user = () => `scan-user-${++account}`;

beforeAll(async () => {
  db = await startDatabase();
});

const ANSWER = JSON.stringify({ flagged: true, quickScan: [], moves: { e2e4: 0 } });

async function addPuzzle(userId: string, key = 'k1', answer = ANSWER): Promise<string> {
  const rows = await asUser(db, userId, (q) =>
    q<{ id: string }>(
      `insert into public.scan_puzzles (content_key, fen_before, last_move, answer, version)
         values ($1, 'fen', 'e7e5', $2::jsonb, 1)
       on conflict (user_id, content_key) do update set answer = excluded.answer
       returning id`,
      [key, answer],
    ),
  );
  return rows[0].id;
}

async function addRun(userId: string, scope: 'all' | 'review', queue: string[]): Promise<string> {
  const id = crypto.randomUUID();
  await asUser(db, userId, (q) =>
    q(
      `insert into public.scan_runs (id, scope, mode, queue, started_at)
         values ($1, $2, 'randomGlobal', $3::uuid[], now())`,
      [id, scope, queue],
    ),
  );
  return id;
}

async function addAttempt(userId: string, puzzleId: string, runId: string | null = null): Promise<string> {
  const id = crypto.randomUUID();
  await asUser(db, userId, (q) =>
    q(
      `insert into public.scan_attempts (id, puzzle_id, run_id, result, flag_call, detail, played_at)
         values ($1, $2, $3, 'solved', true, '{"steps":{}}', now())
       on conflict (id) do nothing`,
      [id, puzzleId, runId],
    ),
  );
  return id;
}

const count = (userId: string, table: string) =>
  asUser(db, userId, (q) => q<{ n: number }>(`select count(*)::int as n from public.${table}`)).then(
    (rows) => rows[0].n,
  );

describe('scan tables', () => {
  it('updates a re-sent puzzle instead of adding a second one', async () => {
    const me = user();
    const first = await addPuzzle(me, 'same');
    const second = await addPuzzle(me, 'same', JSON.stringify({ flagged: false }));
    expect(second).toBe(first);
    const rows = await asUser(db, me, (q) => q<{ answer: { flagged: boolean } }>('select answer from public.scan_puzzles'));
    expect(rows.map((r) => r.answer.flagged)).toEqual([false]);
  });

  it('keeps one run per scope', async () => {
    const me = user();
    const p = await addPuzzle(me);
    await addRun(me, 'all', [p]);
    await expect(addRun(me, 'all', [p])).rejects.toThrow();
    await addRun(me, 'review', [p]);
    expect(await count(me, 'scan_runs')).toBe(2);
  });

  it('refuses an unknown scope, mode or result', async () => {
    const me = user();
    const p = await addPuzzle(me);
    await expect(addRun(me, 'collection' as 'all', [p])).rejects.toThrow();
    await expect(
      asUser(db, me, (q) =>
        q(
          `insert into public.scan_attempts (id, puzzle_id, result, detail, played_at)
             values (gen_random_uuid(), $1, 'passed', '{}', now())`,
          [p],
        ),
      ),
    ).rejects.toThrow();
  });

  it('deletes attempts with their puzzle and unlinks them from a deleted run', async () => {
    const me = user();
    const p1 = await addPuzzle(me, 'a');
    const p2 = await addPuzzle(me, 'b');
    const r = await addRun(me, 'all', [p1, p2]);
    await addAttempt(me, p1, r);
    await addAttempt(me, p2, r);
    await asUser(db, me, (q) => q('delete from public.scan_puzzles where id = $1', [p1]));
    expect(await count(me, 'scan_attempts')).toBe(1);
    await asUser(db, me, (q) => q('delete from public.scan_runs where id = $1', [r]));
    const rows = await asUser(db, me, (q) => q<{ run_id: string | null }>('select run_id from public.scan_attempts'));
    expect(rows).toEqual([{ run_id: null }]);
  });

  it('resets scan progress without touching the puzzles', async () => {
    const me = user();
    const p = await addPuzzle(me);
    const r = await addRun(me, 'all', [p]);
    await addAttempt(me, p, r);
    await asUser(db, me, async (q) => {
      await q('delete from public.scan_attempts');
      await q('delete from public.scan_runs');
    });
    expect(await count(me, 'scan_puzzles')).toBe(1);
    expect(await count(me, 'scan_attempts')).toBe(0);
  });
});

describe('scan access rules', () => {
  it('shows a second account nothing, and lets it change nothing', async () => {
    const alice = user();
    const mallory = user();
    const p = await addPuzzle(alice);
    const r = await addRun(alice, 'all', [p]);
    await addAttempt(alice, p, r);

    for (const table of ['scan_puzzles', 'scan_runs', 'scan_attempts']) {
      expect(await count(mallory, table)).toBe(0);
      await asUser(db, mallory, (q) => q(`delete from public.${table}`));
      expect(await count(alice, table)).toBe(1);
    }
    await asUser(db, mallory, (q) => q(`update public.scan_puzzles set answer = '{}'`));
    const rows = await asUser(db, alice, (q) => q<{ answer: object }>('select answer from public.scan_puzzles'));
    expect(rows[0].answer).toEqual(JSON.parse(ANSWER));
  });

  it('refuses rows pointing at another account’s puzzle or run', async () => {
    const alice = user();
    const mallory = user();
    const p = await addPuzzle(alice);
    const r = await addRun(alice, 'all', [p]);
    await expect(addAttempt(mallory, p)).rejects.toThrow();
    const own = await addPuzzle(mallory);
    await expect(addAttempt(mallory, own, r)).rejects.toThrow();
  });

  it('refuses rows written in another account’s name', async () => {
    const alice = user();
    await expect(
      asUser(db, user(), (q) =>
        q(
          `insert into public.scan_puzzles (user_id, content_key, fen_before, last_move, answer, version)
             values ($1, 'x', 'fen', 'e2e4', '{}', 1)`,
          [alice],
        ),
      ),
    ).rejects.toThrow(/row-level security/);
  });

  it('never changes a run or an attempt once stored', async () => {
    const me = user();
    const p = await addPuzzle(me);
    await addAttempt(me, p, await addRun(me, 'all', [p]));
    for (const sql of [
      `update public.scan_runs set mode = 'reviewMistakes'`,
      `update public.scan_attempts set result = 'failed'`,
      `update public.scan_puzzles set added_at = now()`,
      `update public.scan_puzzles set content_key = 'other'`,
    ]) {
      await expect(asUser(db, me, (q) => q(sql))).rejects.toThrow(/permission denied/);
    }
  });
});
