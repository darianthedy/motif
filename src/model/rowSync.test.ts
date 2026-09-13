import type { PGlite } from '@electric-sql/pglite';
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { asUser, pgTransport, startServer } from '../test/pgServer';
import type { Counting } from '../test/pgServer';
import { uci } from './move';
import type { Collection, Puzzle } from './puzzle';
import { canonical, rebase } from './rows';
import { PAGE_SIZE, PRIMARY_KEYS, syncRows } from './rowSync';
import type { Transport } from './rowSync';
import { completeCurrent, startSession } from './session';
import {
  deleteCollection,
  deletePuzzle,
  emptyState,
  recentPuzzleIds,
  recordResult,
  renameCollection,
  resetProgress,
  saveSession,
  clearSession,
  setPuzzleComment,
} from './state';
import type { AppState } from './state';
import { exportState, parseState } from './storage';

const FEN = '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1';
const square = (i: number) => `${'abcdefgh'[i % 8]}${1 + (Math.floor(i / 8) % 8)}`;

/** A distinct, valid puzzle per `n`: same position, a different answer. */
function puzzle(n: number, addedAt = 1000): Puzzle {
  return {
    id: crypto.randomUUID(),
    fen: FEN,
    solutions: [[uci(`${square(n % 64)}${square(63 - (Math.floor(n / 64) % 64))}`)]],
    tags: [],
    addedAt,
  };
}

/** A collection of `count` puzzles, as an import on one device would create it. */
function library(name: string, numbers: number[], createdAt = 1000): AppState {
  const state = emptyState();
  const collection: Collection = { id: crypto.randomUUID(), name, createdAt, puzzleIds: [] };
  for (const n of numbers) {
    const p = puzzle(n, createdAt);
    state.puzzles[p.id] = p;
    collection.puzzleIds.push(p.id);
  }
  state.collections.push(collection);
  return state;
}

/** Content, ignoring the sync record: what a user would see. */
const visible = (state: AppState) => canonical({ ...state, sync: undefined });

const answers = (state: AppState) =>
  state.collections.map((c) => ({
    name: c.name,
    puzzles: c.puzzleIds.map((id) => state.puzzles[id].solutions[0][0]),
  }));

let db: PGlite;
let clock: number;
// One database for the file — booting Postgres per test costs most of a
// second — with fresh accounts per test, which RLS keeps apart exactly as it
// keeps real users apart.
let alice: string;
let mallory: string;
let run = 0;

beforeAll(async () => {
  db = await startServer();
});

beforeEach(() => {
  run++;
  alice = `alice-${run}`;
  mallory = `mallory-${run}`;
  clock = 1_000_000;
});

class Device {
  state: AppState;
  readonly userId: string;
  counting: Counting = { pulls: 0, upserts: 0 };
  transport: Transport;
  constructor(state: AppState, userId = alice) {
    this.state = state;
    this.userId = userId;
    this.transport = pgTransport(db, userId, this.counting);
  }
  async sync() {
    this.state = await syncRows(this.state, this.userId, this.transport, () => ++clock);
    return this.state;
  }
  edit(fn: (state: AppState) => AppState) {
    this.state = fn(this.state);
  }
}

async function rows(table: string, userId = alice) {
  return asUser(db, userId, (q) =>
    q<Record<string, unknown>>(
      `select * from public.${table}${table === 'libraries' ? '' : ' order by revision'}`,
    ),
  );
}

describe('the first sync', () => {
  it('stores every puzzle, collection and membership as its own row', async () => {
    const phone = new Device(library('Back rank', [1, 2, 3]));
    await phone.sync();

    const puzzles = await rows('puzzles');
    expect(puzzles).toHaveLength(3);
    expect(puzzles.every((row) => row.user_id === alice && row.deleted_at === null)).toBe(true);
    expect(await rows('collections')).toHaveLength(1);
    expect(await rows('collection_puzzles')).toHaveLength(3);
    expect(await rows('library_settings')).toHaveLength(1);
  });

  it('gives a second device the library, in order', async () => {
    const phone = new Device(library('Back rank', [5, 1, 9]));
    await phone.sync();

    const laptop = new Device(emptyState());
    await laptop.sync();
    expect(answers(laptop.state)).toEqual(answers(phone.state));
    expect(Object.keys(laptop.state.puzzles).sort()).toEqual(Object.keys(phone.state.puzzles).sort());
  });

  it('makes no change and no write when nothing moved', async () => {
    const phone = new Device(library('Back rank', [1, 2]));
    await phone.sync();
    // The sync after a push reads that push back once: the cursor cannot skip
    // ahead of rows another device may have written in between.
    await phone.sync();
    const before = phone.state;
    phone.counting.upserts = 0;

    await phone.sync();
    expect(phone.state, 'the same object, so React sees no change').toBe(before);
    expect(phone.counting.upserts).toBe(0);
  });
});

describe('deletion', () => {
  it('reaches the other device instead of coming back', async () => {
    const phone = new Device(library('Back rank', [1, 2, 3]));
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();

    const doomed = phone.state.collections[0].puzzleIds[1];
    phone.edit((s) => deletePuzzle(recordResult(s, doomed, 'failed', 1, ++clock), doomed));
    await phone.sync();
    await laptop.sync();
    await phone.sync();

    expect(laptop.state.puzzles[doomed]).toBeUndefined();
    expect(phone.state.puzzles[doomed], 'and it did not come back').toBeUndefined();
    expect(laptop.state.collections[0].puzzleIds).toHaveLength(2);

    const stored = (await rows('puzzles')).find((row) => row.id === doomed)!;
    expect(stored.deleted_at, 'kept as a marked row').not.toBeNull();
  });

  it('is not undone by a device that still had the puzzle and changed something else', async () => {
    const phone = new Device(library('Back rank', [1, 2]));
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();

    const [doomed, kept] = phone.state.collections[0].puzzleIds;
    phone.edit((s) => deletePuzzle(s, doomed));
    await phone.sync();

    // The laptop has not heard yet, edits the other puzzle, then syncs.
    laptop.edit((s) => setPuzzleComment(s, kept, 'nice'));
    await laptop.sync();
    await phone.sync();

    expect(laptop.state.puzzles[doomed]).toBeUndefined();
    expect(phone.state.puzzles[doomed]).toBeUndefined();
    expect(phone.state.puzzles[kept].comment).toBe('nice');
  });

  it('wins over an edit to the same puzzle made elsewhere', async () => {
    const phone = new Device(library('Back rank', [1, 2]));
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();

    const doomed = phone.state.collections[0].puzzleIds[0];
    phone.edit((s) => deletePuzzle(s, doomed));
    await phone.sync();
    laptop.edit((s) => setPuzzleComment(s, doomed, 'too late'));
    await laptop.sync();

    expect(laptop.state.puzzles[doomed]).toBeUndefined();
    const stored = (await rows('puzzles')).find((row) => row.id === doomed)!;
    expect(stored.deleted_at).not.toBeNull();
  });

  it('removes a whole collection and the puzzles only it held', async () => {
    const phone = new Device(library('Back rank', [1, 2]));
    phone.edit((s) => {
      const other = library('Forks', [3], 2000);
      return {
        ...s,
        puzzles: { ...s.puzzles, ...other.puzzles },
        collections: [...s.collections, ...other.collections],
      };
    });
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();

    phone.edit((s) => deleteCollection(s, s.collections[0].id));
    await phone.sync();
    await laptop.sync();

    expect(laptop.state.collections.map((c) => c.name)).toEqual(['Forks']);
    expect(Object.keys(laptop.state.puzzles)).toHaveLength(1);
  });

  it('lets a deleted puzzle be imported again as a new one', async () => {
    const phone = new Device(library('Back rank', [1]));
    await phone.sync();
    phone.edit((s) => deletePuzzle(s, s.collections[0].puzzleIds[0]));
    await phone.sync();

    const again = puzzle(1);
    phone.edit((s) => ({
      ...s,
      puzzles: { ...s.puzzles, [again.id]: again },
      collections: [{ ...s.collections[0], puzzleIds: [again.id] }],
    }));
    await phone.sync();

    const live = (await rows('puzzles')).filter((row) => row.deleted_at === null);
    expect(live.map((row) => row.id)).toEqual([again.id]);
  });
});

describe('two devices importing the same puzzles', () => {
  it('ends with one copy of each, under one id, with progress from both', async () => {
    const phone = new Device(library('Back rank', [1, 2]));
    const laptop = new Device(library('Back rank', [1, 2]));
    const laptopId = laptop.state.collections[0].puzzleIds[0];
    laptop.edit((s) => recordResult(s, laptopId, 'solved', 0, ++clock));

    await phone.sync();
    await laptop.sync();
    await phone.sync();

    expect(Object.keys(laptop.state.puzzles)).toHaveLength(2);
    expect(laptop.state.collections).toHaveLength(1);
    expect(visible(laptop.state)).toBe(visible(phone.state));
    // The phone's ids won, being on the server first; the laptop's solve moved
    // onto the phone's id rather than being lost with its own.
    const winner = phone.state.collections[0].puzzleIds[0];
    expect(laptop.state.progress[winner]?.status).toBe('solved');
    expect((await rows('puzzles')).filter((row) => row.deleted_at === null)).toHaveLength(2);
  });

  it('resolves the race when both push before either has seen the other', async () => {
    const phone = new Device(library('Back rank', [1, 2]));
    const laptop = new Device(library('Back rank', [2, 3]));

    // Hold the laptop's first push until the phone has finished syncing, so
    // the laptop pulled an empty server and then collides on insert.
    let release!: () => void;
    const gate = new Promise<void>((resolve) => (release = resolve));
    const upsert = laptop.transport.upsert;
    let first = true;
    laptop.transport.upsert = async (...args) => {
      if (first) {
        first = false;
        await gate;
      }
      return upsert(...args);
    };

    const laptopSync = laptop.sync();
    await new Promise((resolve) => setTimeout(resolve, 50));
    await phone.sync();
    release();
    await laptopSync;
    await phone.sync();

    expect(answers(laptop.state)[0].puzzles).toHaveLength(3);
    expect(visible(laptop.state)).toBe(visible(phone.state));
    expect((await rows('collections')).filter((row) => row.deleted_at === null)).toHaveLength(1);
  });
});

describe('progress', () => {
  it('counts attempts from both devices and takes the latest status', async () => {
    const phone = new Device(library('Back rank', [1]));
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();
    const id = phone.state.collections[0].puzzleIds[0];

    phone.edit((s) => recordResult(s, id, 'solved', 0, ++clock));
    laptop.edit((s) => recordResult(s, id, 'failed', 1, ++clock));
    laptop.edit((s) => recordResult(s, id, 'failed', 1, ++clock));
    await phone.sync();
    await laptop.sync();
    await phone.sync();

    for (const device of [phone, laptop]) {
      expect(device.state.progress[id].attempts).toBe(2);
      expect(device.state.progress[id].status).toBe('failed');
      expect(device.state.progress[id].firstSolvedAt).toBeDefined();
    }
  });

  it('keeps both solves when two devices push at the same moment', async () => {
    const phone = new Device(library('Back rank', [1]));
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();
    const id = phone.state.collections[0].puzzleIds[0];

    phone.edit((s) => recordResult(s, id, 'failed', 3, ++clock));
    laptop.edit((s) => recordResult(recordResult(s, id, 'failed', 1, ++clock), id, 'solved', 0, ++clock));

    // Both pull before either pushes; only the server trigger can merge them.
    await Promise.all([phone.sync(), laptop.sync()]);
    await phone.sync();
    await laptop.sync();

    const [stored] = await rows('progress');
    expect(stored.attempts).toBe(2);
    expect(stored.mistakes).toBe(3);
    expect(stored.status).toBe('solved');
    expect(phone.state.progress[id].attempts).toBe(2);
  });

  it('gives the recent list to the other device, since it is read from progress', async () => {
    const phone = new Device(library('Back rank', [1, 2, 3]));
    const [a, b] = phone.state.collections[0].puzzleIds;
    phone.edit((s) => recordResult(recordResult(s, a, 'solved', 0, ++clock), b, 'solved', 0, ++clock));
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();

    expect(recentPuzzleIds(laptop.state)).toEqual([b, a]);
  });
});

describe('resetting progress', () => {
  it('clears progress and sessions on the other device too', async () => {
    const phone = new Device(library('Back rank', [1, 2]));
    const [a, b] = phone.state.collections[0].puzzleIds;
    phone.edit((s) => recordResult(recordResult(s, a, 'solved', 0, ++clock), b, 'failed', 1, ++clock));
    phone.edit((s) =>
      saveSession(s, s.collections[0].id, startSession('ordered', s.collections[0].id, [a, b], Math.random, ++clock)),
    );
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();
    expect(Object.keys(laptop.state.progress)).toHaveLength(2);

    phone.edit((s) => resetProgress(s, ++clock));
    await phone.sync();
    await laptop.sync();

    expect(laptop.state.progress).toEqual({});
    expect(laptop.state.sessions).toEqual({});
    expect(laptop.state.progressResetAt).toBe(phone.state.progressResetAt);
  });

  it('keeps an attempt made after the reset, and drops one made before it', async () => {
    const phone = new Device(library('Back rank', [1, 2]));
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();
    const [a, b] = phone.state.collections[0].puzzleIds;

    // Offline on the laptop: one attempt before the phone's reset...
    laptop.edit((s) => recordResult(s, a, 'solved', 0, ++clock));
    phone.edit((s) => resetProgress(s, ++clock));
    // ...and one after it.
    laptop.edit((s) => recordResult(s, b, 'failed', 1, ++clock));
    await phone.sync();
    await laptop.sync();
    await phone.sync();

    for (const device of [phone, laptop]) {
      expect(device.state.progress[a], 'from before the reset').toBeUndefined();
      expect(device.state.progress[b]?.status, 'from after it').toBe('failed');
    }
  });
});

describe('collections', () => {
  it('carries a rename to the other device', async () => {
    const phone = new Device(library('Back rank', [1]));
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();

    phone.edit((s) => renameCollection(s, s.collections[0].id, 'Back-rank mates'));
    await phone.sync();
    await laptop.sync();
    expect(laptop.state.collections[0].name).toBe('Back-rank mates');
  });

  it('keeps the order when a puzzle is added to the end on another device', async () => {
    const phone = new Device(library('Back rank', [1, 2]));
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();

    const extra = puzzle(7);
    laptop.edit((s) => ({
      ...s,
      puzzles: { ...s.puzzles, [extra.id]: extra },
      collections: [{ ...s.collections[0], puzzleIds: [...s.collections[0].puzzleIds, extra.id] }],
    }));
    await laptop.sync();
    await phone.sync();
    expect(phone.state.collections[0].puzzleIds.at(-1)).toBe(extra.id);
    expect(answers(phone.state)).toEqual(answers(laptop.state));
  });

  it('does not re-upload the rest of a collection when one puzzle goes', async () => {
    const phone = new Device(library('Back rank', [1, 2, 3, 4, 5]));
    await phone.sync();
    const before = await rows('collection_puzzles');

    phone.edit((s) => deletePuzzle(s, s.collections[0].puzzleIds[0]));
    await phone.sync();

    const after = await rows('collection_puzzles');
    const changed = after.filter(
      (row) => before.find((b) => b.puzzle_id === row.puzzle_id)!.revision !== row.revision,
    );
    expect(changed, 'only the removed membership is written').toHaveLength(1);
  });
});

describe('sessions', () => {
  it('follow the device that played most recently, and end everywhere', async () => {
    const phone = new Device(library('Back rank', [1, 2, 3]));
    const key = phone.state.collections[0].id;
    phone.edit((s) =>
      saveSession(s, key, startSession('ordered', key, s.collections[0].puzzleIds, Math.random, ++clock)),
    );
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();
    expect(laptop.state.sessions[key]?.cursor).toBe(1);

    laptop.edit((s) => saveSession(s, key, completeCurrent(s.sessions[key], 'solved', ++clock)));
    await laptop.sync();
    await phone.sync();
    expect(phone.state.sessions[key].completed).toBe(1);

    phone.edit((s) => clearSession(s, key));
    await phone.sync();
    await laptop.sync();
    expect(laptop.state.sessions[key]).toBeUndefined();
  });
});

describe('moving off the old blob', () => {
  it('turns an existing blob into rows, then removes it', async () => {
    const old = library('Back rank', [1, 2]);
    await db.query(`insert into public.libraries (user_id, state) values ($1, $2::jsonb)`, [
      alice,
      JSON.stringify(old),
    ]);

    const fresh = new Device(emptyState());
    await fresh.sync();

    expect(answers(fresh.state)).toEqual(answers(old));
    expect(await rows('puzzles')).toHaveLength(2);
    expect(await rows('libraries')).toHaveLength(0);
  });

  it('refuses writes to the blob from an app that has not updated', async () => {
    await expect(
      asUser(db, alice, (q) =>
        q(`insert into public.libraries (user_id, state) values ($1, '{}'::jsonb)`, [alice]),
      ),
    ).rejects.toThrow();
  });
});

describe('privacy', () => {
  it("never shows one account another's rows", async () => {
    await new Device(library('Back rank', [1, 2])).sync();
    const stranger = new Device(emptyState(), mallory);
    await stranger.sync();

    expect(Object.keys(stranger.state.puzzles)).toHaveLength(0);
    for (const table of ['puzzles', 'collections', 'collection_puzzles', 'progress', 'library_settings']) {
      expect(await rows(table, mallory), table).toHaveLength(
        table === 'library_settings' ? 1 : 0,
      );
    }
  });

  it('refuses a row written under someone else’s id', async () => {
    await expect(
      asUser(db, mallory, (q) =>
        q(
          `insert into public.collections (user_id, id, name, created_at)
             values ($1, 'x', 'Mine now', 1)`,
          [alice],
        ),
      ),
    ).rejects.toThrow(/row-level security/);
  });

  it('has no way to delete a row outright', async () => {
    await new Device(library('Back rank', [1])).sync();
    await expect(
      asUser(db, alice, (q) => q('delete from public.collection_puzzles')),
    ).rejects.toThrow(/permission denied/);
  });
});

describe('large libraries', () => {
  it('pulls across pages', async () => {
    const numbers = Array.from({ length: PAGE_SIZE + 50 }, (_, i) => i);
    const phone = new Device(library('Big book', numbers));
    await phone.sync();

    const laptop = new Device(emptyState());
    await laptop.sync();
    expect(Object.keys(laptop.state.puzzles)).toHaveLength(numbers.length);
    expect(answers(laptop.state)).toEqual(answers(phone.state));
  }, 60_000);
});

describe('changes made while a sync is in flight', () => {
  it('are kept, and sent on the next sync', async () => {
    const phone = new Device(library('Back rank', [1, 2]));
    await phone.sync();
    const laptop = new Device(emptyState());
    await laptop.sync();
    const [a, b] = laptop.state.collections[0].puzzleIds;
    phone.edit((s) => setPuzzleComment(s, a, 'from the phone'));
    await phone.sync();

    const used = laptop.state;
    const merged = await syncRows(used, alice, laptop.transport, () => ++clock);
    // Recorded on the laptop while that sync was talking to the server.
    const live = recordResult(used, b, 'solved', 0, ++clock);

    laptop.state = rebase(used, live, merged);
    expect(laptop.state.puzzles[a].comment, 'the sync result').toBe('from the phone');
    expect(laptop.state.progress[b]?.status, 'the solve made meanwhile').toBe('solved');

    await laptop.sync();
    await phone.sync();
    expect(phone.state.progress[b]?.status).toBe('solved');
  });
});

describe('backups', () => {
  it('leave the sync record out', async () => {
    const phone = new Device(library('Back rank', [1]));
    await phone.sync();
    expect(phone.state.sync).toBeDefined();
    expect(JSON.parse(exportState(phone.state)).sync).toBeUndefined();
  });

  it('keep the sync record through a reload', async () => {
    const phone = new Device(library('Back rank', [1]));
    await phone.sync();
    const reloaded = parseState(JSON.parse(JSON.stringify(phone.state)));
    expect(canonical(reloaded.sync)).toBe(canonical(phone.state.sync));
  });
});

describe('the server’s own conflict rules', () => {
  // What the triggers do when a push races another. The device-level tests
  // above reach these only when the timing happens to line up; here the
  // conflicting writes are made directly.
  const put = (table: 'puzzles' | 'progress' | 'sessions', row: Record<string, unknown>) =>
    pgTransport(db, alice).upsert(table, [{ user_id: alice, ...row }], PRIMARY_KEYS[table]);

  const puzzleRow = {
    id: 'p1',
    content_key: 'k1',
    fen: FEN,
    setup_move: null,
    solutions: [['a1a8']],
    add_piece: null,
    tags: [],
    comment: null,
    source_id: null,
    rating: null,
    added_at: 1,
  };

  it('keeps a deleted puzzle deleted whatever is pushed over it', async () => {
    await put('puzzles', { ...puzzleRow, deleted_at: null });
    await put('puzzles', { ...puzzleRow, deleted_at: 50 });
    const [back] = await put('puzzles', { ...puzzleRow, comment: 'stale', deleted_at: null });
    expect(back.deleted_at, 'returned to the pusher, so it learns').toBe(50);
    expect(back.comment).toBeNull();
  });

  it('does not let a deletion erase an attempt made after it', async () => {
    await put('puzzles', { ...puzzleRow, deleted_at: null });
    const progress = {
      puzzle_id: 'p1',
      status: 'solved',
      attempts: 1,
      mistakes: 0,
      first_solved_at: 100,
    };
    await put('progress', { ...progress, last_attempt_at: 100, deleted_at: null });
    const [kept] = await put('progress', { ...progress, last_attempt_at: 100, deleted_at: 90 });
    expect(kept.deleted_at).toBeNull();
    const [gone] = await put('progress', { ...progress, last_attempt_at: 100, deleted_at: 110 });
    expect(gone.deleted_at).toBe(110);
  });

  it('keeps the more recently played session', async () => {
    const session = (at: number) => ({ key: 's', session: { queue: ['p1'] }, last_active_at: at, deleted_at: null });
    await put('sessions', session(200));
    const [held] = await put('sessions', session(100));
    expect(held.last_active_at).toBe(200);
  });
});
