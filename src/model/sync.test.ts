import { describe, expect, it } from 'vitest';
import { importJson } from './import/json';
import { contentKey } from './puzzle';
import { completeCurrent, startSession } from './session';
import { applyImport, emptyState, recordResult, saveSession, statusOf } from './state';
import type { AppState } from './state';
import { mergeStates } from './sync';

const MATE_FEN = '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1';
const OTHER_FEN = '3r2k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1';

function file(name: string, fens: string[], extra = '') {
  const puzzles = fens
    .map((fen) => `{ "fen": "${fen}", "solutions": [["a1a8"]]${extra} }`)
    .join(',');
  return `{ "collection": "${name}", "puzzles": [${puzzles}] }`;
}

/** A library built independently, as a second device would build it. */
function device(name: string, fens: string[], extra = ''): AppState {
  return applyImport(emptyState(), importJson(file(name, fens, extra))).state;
}

const idFor = (state: AppState, fen: string) =>
  Object.values(state.puzzles).find((puzzle) => puzzle.fen === fen)!.id;

describe('merging independent imports', () => {
  it('does not duplicate a puzzle both devices imported', () => {
    const phone = device('Test', [MATE_FEN, OTHER_FEN]);
    const laptop = device('Test', [MATE_FEN, OTHER_FEN]);

    // The two devices generated different ids for the same puzzles.
    expect(Object.keys(phone.puzzles)).not.toEqual(Object.keys(laptop.puzzles));

    const merged = mergeStates(phone, laptop);
    expect(Object.keys(merged.puzzles)).toHaveLength(2);
    expect(merged.collections).toHaveLength(1);
    expect(merged.collections[0].puzzleIds).toHaveLength(2);
  });

  it('is idempotent', () => {
    const phone = device('Test', [MATE_FEN, OTHER_FEN]);
    const laptop = device('Test', [MATE_FEN]);

    const once = mergeStates(phone, laptop);
    const twice = mergeStates(once, laptop);
    expect(Object.keys(twice.puzzles)).toHaveLength(Object.keys(once.puzzles).length);
    expect(twice.collections[0].puzzleIds).toEqual(once.collections[0].puzzleIds);
  });

  it('reaches the same library whichever side computes it', () => {
    const phone = device('Test', [MATE_FEN]);
    const laptop = device('Test', [OTHER_FEN]);

    const fromPhone = mergeStates(phone, laptop);
    const fromLaptop = mergeStates(laptop, phone);

    const keys = (state: AppState) =>
      Object.values(state.puzzles).map(contentKey).sort();
    expect(keys(fromPhone)).toEqual(keys(fromLaptop));
    expect(fromPhone.collections.map((c) => c.name)).toEqual(
      fromLaptop.collections.map((c) => c.name),
    );
  });

  it('unions collections of the same name', () => {
    const phone = device('Test', [MATE_FEN]);
    const laptop = device('Test', [OTHER_FEN]);
    const merged = mergeStates(phone, laptop);

    expect(merged.collections).toHaveLength(1);
    expect(merged.collections[0].puzzleIds).toHaveLength(2);
  });

  it('keeps differently named collections apart', () => {
    const merged = mergeStates(device('Mate in one', [MATE_FEN]), device('Mate in two', [OTHER_FEN]));
    expect(merged.collections.map((c) => c.name)).toEqual(['Mate in one', 'Mate in two']);
  });
});

describe('merging progress', () => {
  it('keeps work done on the other device', () => {
    const phone = device('Test', [MATE_FEN, OTHER_FEN]);
    const laptop = device('Test', [MATE_FEN, OTHER_FEN]);

    const solvedOnPhone = recordResult(phone, idFor(phone, MATE_FEN), 'solved', 0, 1000);
    // The laptop never saw that solve — under last-write-wins it would erase it.
    const merged = mergeStates(solvedOnPhone, laptop);

    const key = contentKey(Object.values(solvedOnPhone.puzzles).find((p) => p.fen === MATE_FEN)!);
    const mergedId = Object.values(merged.puzzles).find((p) => contentKey(p) === key)!.id;
    expect(statusOf(merged, mergedId)).toBe('solved');
  });

  it('takes the status from the most recent attempt', () => {
    const phone = device('Test', [MATE_FEN]);
    const laptop = device('Test', [MATE_FEN]);

    const failedEarly = recordResult(phone, idFor(phone, MATE_FEN), 'failed', 1, 1000);
    const solvedLate = recordResult(laptop, idFor(laptop, MATE_FEN), 'solved', 0, 5000);

    const merged = mergeStates(failedEarly, solvedLate);
    const id = Object.keys(merged.progress)[0];
    expect(merged.progress[id].status).toBe('solved');
    expect(merged.progress[id].lastAttemptAt).toBe(5000);
  });

  it('does not double-count attempts both devices already knew about', () => {
    const phone = device('Test', [MATE_FEN]);
    const id = idFor(phone, MATE_FEN);

    // A shared ancestor with two attempts, then one more on this device.
    let shared = recordResult(phone, id, 'failed', 1, 1000);
    shared = recordResult(shared, id, 'failed', 1, 2000);
    const advanced = recordResult(shared, id, 'solved', 0, 3000);

    const merged = mergeStates(advanced, shared);
    expect(merged.progress[id].attempts, 'max, not sum').toBe(3);
    expect(merged.progress[id].mistakes).toBe(2);
  });

  it('keeps the earliest first solve', () => {
    const phone = device('Test', [MATE_FEN]);
    const laptop = device('Test', [MATE_FEN]);
    const early = recordResult(phone, idFor(phone, MATE_FEN), 'solved', 0, 1000);
    const late = recordResult(laptop, idFor(laptop, MATE_FEN), 'solved', 0, 9000);

    const merged = mergeStates(late, early);
    expect(merged.progress[Object.keys(merged.progress)[0]].firstSolvedAt).toBe(1000);
  });
});

describe('merging sessions', () => {
  it('keeps the more recently active session rather than interleaving', () => {
    const phone = device('Test', [MATE_FEN, OTHER_FEN]);
    const laptop = device('Test', [MATE_FEN, OTHER_FEN]);

    const phoneSession = startSession('ordered', 'c', Object.keys(phone.puzzles), Math.random, 1000);
    const laptopSession = completeCurrent(
      startSession('ordered', 'c', Object.keys(laptop.puzzles), Math.random, 5000),
      'solved',
      5000,
    );

    const merged = mergeStates(
      saveSession(phone, 'c', phoneSession),
      saveSession(laptop, 'c', laptopSession),
    );
    expect(merged.sessions['c'].lastActiveAt).toBe(5000);
    expect(merged.sessions['c'].completed).toBe(1);
  });

  it('rewrites session ids onto the surviving puzzles', () => {
    const phone = device('Test', [MATE_FEN, OTHER_FEN]);
    const laptop = device('Test', [MATE_FEN, OTHER_FEN]);

    const session = startSession('ordered', 'c', Object.keys(phone.puzzles), Math.random, 9000);
    const merged = mergeStates(saveSession(phone, 'c', session), laptop);

    // Every id the session refers to must still exist after the id remap.
    for (const id of merged.sessions['c'].queue) {
      expect(merged.puzzles[id], `queue id ${id} survived`).toBeDefined();
    }
    expect(merged.sessions['c'].current).not.toBeNull();
    expect(merged.puzzles[merged.sessions['c'].current!]).toBeDefined();
  });

  it('drops a session whose puzzles are all gone', () => {
    const phone = device('Test', [MATE_FEN]);
    const stale = saveSession(phone, 'c', {
      ...startSession('ordered', 'c', ['ghost-id'], Math.random, 1000),
    });
    const merged = mergeStates(stale, emptyState());
    expect(merged.sessions['c']).toBeUndefined();
  });
});

describe('merging metadata', () => {
  it('takes an edited comment from the more recent import', () => {
    const phone = device('Test', [MATE_FEN]);
    const laptop = device('Test', [MATE_FEN], ', "comment": "Now annotated"');
    // Make the laptop's copy unambiguously newer.
    const id = idFor(laptop, MATE_FEN);
    laptop.puzzles[id] = { ...laptop.puzzles[id], addedAt: Date.now() + 10_000 };

    const merged = mergeStates(phone, laptop);
    expect(Object.values(merged.puzzles)[0].comment).toBe('Now annotated');
  });

  it('does not erase a comment the newer copy simply lacks', () => {
    const phone = device('Test', [MATE_FEN], ', "comment": "Kept"');
    const laptop = device('Test', [MATE_FEN]);
    const id = idFor(laptop, MATE_FEN);
    laptop.puzzles[id] = { ...laptop.puzzles[id], addedAt: Date.now() + 10_000 };

    expect(Object.values(mergeStates(phone, laptop).puzzles)[0].comment).toBe('Kept');
  });
});

describe('merging with an empty side', () => {
  it('is a no-op against an empty library', () => {
    const phone = device('Test', [MATE_FEN, OTHER_FEN]);
    const merged = mergeStates(phone, emptyState());
    expect(Object.keys(merged.puzzles)).toHaveLength(2);
    expect(merged.collections[0].name).toBe('Test');
  });

  it('adopts a remote library on a fresh device', () => {
    const remote = device('Test', [MATE_FEN, OTHER_FEN]);
    const merged = mergeStates(emptyState(), remote);
    expect(Object.keys(merged.puzzles)).toHaveLength(2);
  });
});
