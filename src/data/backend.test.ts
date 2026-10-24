import type { PGlite } from '@electric-sql/pglite';
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { uci } from '../model/move';
import { asUser, pgRest, startDatabase } from '../test/pgServer';
import { emptyLibrary, memoryBackend, restBackend } from './backend';
import type { Attempt, Backend, Collection, GameCollection, NewGame, NewPuzzle, Run } from './backend';

const FEN = '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1';
const square = (i: number) => `${'abcdefgh'[i % 8]}${1 + (Math.floor(i / 8) % 8)}`;

function collection(name = 'Back rank', createdAt = 1_000): Collection {
  return { id: crypto.randomUUID(), name, createdAt };
}

/** A distinct puzzle per `n`: same position, a different answer. */
function puzzle(collectionId: string, n: number, extra: Partial<NewPuzzle> = {}): NewPuzzle {
  return {
    collectionId,
    position: n,
    fen: FEN,
    solutions: [[uci(`${square(n)}${square(63 - n)}`)]],
    tags: [],
    ...extra,
  };
}

function run(scope: string, queue: string[], startedAt = 2_000): Run {
  return { id: crypto.randomUUID(), scope, mode: 'ordered', queue, startedAt };
}

function attempt(puzzleId: string, extra: Partial<Attempt> = {}): Attempt {
  return {
    id: crypto.randomUUID(),
    puzzleId,
    runId: null,
    result: 'solved',
    mistakes: 0,
    hinted: false,
    playedAt: 3_000,
    ...extra,
  };
}

function newGame(collectionId: string, position: number, extra: Partial<NewGame> = {}): NewGame {
  return {
    id: crypto.randomUUID(),
    collectionId,
    position,
    pgn: `[White "Player ${position}"]\n\n1. e4 e5 (1... c5) *\n`,
    orientation: 'w',
    ...extra,
  };
}

const gameCollection = (name = 'Openings', createdAt = 1_000): GameCollection => ({
  id: crypto.randomUUID(),
  name,
  createdAt,
});

let db: PGlite;
let account = 0;

beforeAll(async () => {
  db = await startDatabase();
});

// One database for the file, a fresh account per test: RLS keeps them apart
// exactly as it keeps real users apart.
const backends: [string, () => Backend][] = [
  ['postgres', () => {
    const user = `user-${++account}`;
    return restBackend(pgRest(db, user), user);
  }],
  ['memory', () => memoryBackend()],
];

describe.each(backends)('%s backend', (_, make) => {
  let backend: Backend;

  beforeEach(() => {
    backend = make();
  });

  async function seeded(count = 2) {
    const c = collection();
    await backend.createCollections([c]);
    const puzzles = await backend.importPuzzles(
      Array.from({ length: count }, (_, n) => puzzle(c.id, n)),
    );
    return { collection: c, puzzles };
  }

  it('stores and loads every kind of row', async () => {
    const c = collection('Mates', 1_234);
    await backend.createCollections([c]);
    const [p] = await backend.importPuzzles([
      puzzle(c.id, 0, { tags: ['mate'], comment: 'No luft', sourceId: '187', rating: 900 }),
    ]);
    const [m] = await backend.importPuzzles([
      puzzle(c.id, 1, { solutions: [], addPiece: { color: 'w', type: 'n', square: 'g6' } }),
    ]);
    const r = run(c.id, [p.id, m.id]);
    await backend.saveRun(r);
    const a = attempt(p.id, { runId: r.id, result: 'failed', mistakes: 2, hinted: true });
    await backend.recordAttempts([a]);

    const library = await backend.load();
    expect(library.collections).toEqual([c]);
    expect(library.puzzles).toHaveLength(2);
    expect(library.puzzles.find((x) => x.id === p.id)).toMatchObject({
      collectionId: c.id,
      position: 0,
      solutions: [[expect.any(String)]],
      tags: ['mate'],
      comment: 'No luft',
      sourceId: '187',
      rating: 900,
    });
    expect(library.puzzles.find((x) => x.id === m.id)?.addPiece).toEqual({
      color: 'w',
      type: 'n',
      square: 'g6',
    });
    expect(library.runs).toEqual([r]);
    expect(library.attempts).toEqual([a]);
  });

  it('renames a collection, and lets two share a name', async () => {
    const a = collection('Same');
    const b = collection('Same');
    await backend.createCollections([a, b]);
    await backend.renameCollection(a.id, 'Other');
    const names = (await backend.load()).collections.map((c) => c.name).sort();
    expect(names).toEqual(['Other', 'Same']);
  });

  it('updates a puzzle re-imported into the same collection', async () => {
    const { collection: c, puzzles } = await seeded(1);
    await backend.setComment(puzzles[0].id, 'mine');
    const [again] = await backend.importPuzzles([
      puzzle(c.id, 0, { tags: ['new'], comment: 'from file', rating: 1500, sourceId: '9' }),
    ]);

    expect(again.id).toBe(puzzles[0].id);
    expect(again.addedAt).toBe(puzzles[0].addedAt);
    const library = await backend.load();
    expect(library.puzzles).toHaveLength(1);
    expect(library.puzzles[0]).toMatchObject({
      tags: ['new'],
      comment: 'from file',
      rating: 1500,
      sourceId: '9',
    });
  });

  it('keeps one of a puzzle listed twice in one import', async () => {
    const c = collection();
    await backend.createCollections([c]);
    const stored = await backend.importPuzzles([
      puzzle(c.id, 0, { comment: 'first' }),
      puzzle(c.id, 0, { comment: 'second' }),
    ]);
    expect(stored).toHaveLength(1);
    expect((await backend.load()).puzzles.map((p) => p.comment)).toEqual(['second']);
  });

  it('imports the same puzzle into two collections as two puzzles', async () => {
    const a = collection('A');
    const b = collection('B');
    await backend.createCollections([a, b]);
    const [inA] = await backend.importPuzzles([puzzle(a.id, 0)]);
    const [inB] = await backend.importPuzzles([puzzle(b.id, 0)]);
    expect(inA.id).not.toBe(inB.id);
    expect((await backend.load()).puzzles).toHaveLength(2);
  });

  it('sets and clears a comment', async () => {
    const { puzzles } = await seeded(1);
    await backend.setComment(puzzles[0].id, '  a note ');
    expect((await backend.load()).puzzles[0].comment).toBe('a note');
    await backend.setComment(puzzles[0].id, '   ');
    expect((await backend.load()).puzzles[0].comment).toBeUndefined();
  });

  it('flags and unflags a puzzle, and a re-import keeps the flag', async () => {
    const { collection: c, puzzles } = await seeded(1);
    expect((await backend.load()).puzzles[0].flagged).toBeUndefined();
    await backend.setFlagged(puzzles[0].id, true);
    expect((await backend.load()).puzzles[0].flagged).toBe(true);
    await backend.importPuzzles([puzzle(c.id, 0, { comment: 'again' })]);
    expect((await backend.load()).puzzles[0].flagged).toBe(true);
    await backend.setFlagged(puzzles[0].id, false);
    expect((await backend.load()).puzzles[0].flagged).toBeUndefined();
  });

  it('deletes a puzzle with its attempts', async () => {
    const { puzzles } = await seeded(2);
    await backend.recordAttempts([attempt(puzzles[0].id), attempt(puzzles[1].id)]);
    await backend.deletePuzzle(puzzles[0].id);
    const library = await backend.load();
    expect(library.puzzles.map((p) => p.id)).toEqual([puzzles[1].id]);
    expect(library.attempts.map((a) => a.puzzleId)).toEqual([puzzles[1].id]);
  });

  it('deletes a collection with its puzzles, attempts and run', async () => {
    const { collection: c, puzzles } = await seeded(2);
    const kept = await seeded(1);
    const r = run(c.id, puzzles.map((p) => p.id));
    await backend.saveRun(r);
    await backend.saveRun(run('all', [kept.puzzles[0].id]));
    await backend.recordAttempts([attempt(puzzles[0].id, { runId: r.id }), attempt(kept.puzzles[0].id)]);

    await backend.deleteCollection(c.id);
    const library = await backend.load();
    expect(library.collections.map((x) => x.id)).toEqual([kept.collection.id]);
    expect(library.puzzles.map((p) => p.id)).toEqual([kept.puzzles[0].id]);
    expect(library.attempts.map((a) => a.puzzleId)).toEqual([kept.puzzles[0].id]);
    expect(library.runs.map((x) => x.scope)).toEqual(['all']);
  });

  it('stores an attempt uploaded twice once', async () => {
    const { puzzles } = await seeded(1);
    const a = attempt(puzzles[0].id);
    await backend.recordAttempts([a]);
    await backend.recordAttempts([a, { ...a, result: 'failed' }]);
    expect((await backend.load()).attempts).toEqual([a]);
  });

  it('drops attempts on deleted puzzles and unlinks them from deleted runs', async () => {
    const { puzzles } = await seeded(2);
    const r = run('all', puzzles.map((p) => p.id));
    await backend.deletePuzzle(puzzles[0].id);
    // Neither the run nor the first puzzle exists any more.
    await backend.recordAttempts([
      attempt(puzzles[0].id, { runId: r.id }),
      attempt(puzzles[1].id, { runId: r.id }),
    ]);
    const { attempts } = await backend.load();
    expect(attempts).toHaveLength(1);
    expect(attempts[0]).toMatchObject({ puzzleId: puzzles[1].id, runId: null });
  });

  it('keeps one run per scope, the newest', async () => {
    const { collection: c, puzzles } = await seeded(1);
    const queue = [puzzles[0].id];
    const first = run(c.id, queue, 1_000);
    const second = run(c.id, queue, 2_000);
    const stale = run(c.id, queue, 1_500);
    await backend.saveRun(first);
    await backend.recordAttempts([attempt(puzzles[0].id, { runId: first.id })]);
    await backend.saveRun(second);
    // Uploaded late, from a device that started it before `second`.
    await backend.saveRun(stale);
    await backend.saveRun(second);

    const library = await backend.load();
    expect(library.runs).toEqual([second]);
    // The replaced run's attempts still count as progress.
    expect(library.attempts[0].runId).toBeNull();
  });

  it('keeps runs in different scopes side by side', async () => {
    const { collection: c, puzzles } = await seeded(1);
    const queue = [puzzles[0].id];
    await backend.saveRun(run(c.id, queue));
    await backend.saveRun(run('all', queue));
    await backend.saveRun(run('review', queue));
    expect((await backend.load()).runs).toHaveLength(3);
  });

  it('deletes a run, keeping its attempts', async () => {
    const { puzzles } = await seeded(1);
    const r = run('all', [puzzles[0].id]);
    await backend.saveRun(r);
    await backend.recordAttempts([attempt(puzzles[0].id, { runId: r.id })]);
    await backend.deleteRun(r.id);
    const library = await backend.load();
    expect(library.runs).toEqual([]);
    expect(library.attempts).toMatchObject([{ runId: null }]);
  });

  it('resets progress, keeping the library', async () => {
    const { puzzles } = await seeded(2);
    const r = run('all', puzzles.map((p) => p.id));
    await backend.saveRun(r);
    await backend.recordAttempts(puzzles.map((p) => attempt(p.id, { runId: r.id })));
    await backend.resetProgress();
    const library = await backend.load();
    expect(library.attempts).toEqual([]);
    expect(library.runs).toEqual([]);
    expect(library.puzzles).toHaveLength(2);
    expect(library.collections).toHaveLength(1);
  });

  describe('games', () => {
    async function seededGames(count = 2) {
      const c = gameCollection();
      await backend.createGameCollections([c]);
      const games = Array.from({ length: count }, (_, n) => newGame(c.id, n));
      await backend.addGames(games);
      return { collection: c, games };
    }

    it('stores and loads collections and games', async () => {
      const { collection: c, games } = await seededGames(1);
      await backend.addGames([newGame(c.id, 1, { orientation: 'b' })]);
      const library = await backend.load();
      expect(library.gameCollections).toEqual([c]);
      expect(library.games).toHaveLength(2);
      expect(library.games.find((g) => g.id === games[0].id)).toEqual({
        ...games[0],
        addedAt: expect.any(Number),
      });
      expect(library.games.find((g) => g.id !== games[0].id)?.orientation).toBe('b');
      // Kept apart from puzzle collections.
      expect(library.collections).toEqual([]);
    });

    it('updates a game’s text and orientation', async () => {
      const { games } = await seededGames(1);
      await backend.updateGame(games[0].id, { pgn: '1. d4 *\n' });
      await backend.updateGame(games[0].id, { orientation: 'b' });
      expect((await backend.load()).games[0]).toMatchObject({ pgn: '1. d4 *\n', orientation: 'b' });
    });

    it('reorders games and moves them to another collection', async () => {
      const { collection: a, games } = await seededGames(2);
      const b = gameCollection('Endgames');
      await backend.createGameCollections([b]);
      await backend.placeGames([
        { id: games[0].id, collectionId: a.id, position: 1 },
        { id: games[1].id, collectionId: b.id, position: 0 },
      ]);
      const placed = (await backend.load()).games.map((g) => [g.id, g.collectionId, g.position]);
      expect(placed).toEqual(
        expect.arrayContaining([
          [games[0].id, a.id, 1],
          [games[1].id, b.id, 0],
        ]),
      );
    });

    it('refuses a game in a collection that does not exist', async () => {
      await expect(backend.addGames([newGame(crypto.randomUUID(), 0)])).rejects.toThrow();
    });

    it('renames a collection, and deletes games, and a collection with its games', async () => {
      const { collection: c, games } = await seededGames(3);
      const kept = await seededGames(1);
      await backend.renameGameCollection(c.id, 'Renamed');
      await backend.deleteGames([games[0].id]);
      let library = await backend.load();
      expect(library.gameCollections.find((x) => x.id === c.id)?.name).toBe('Renamed');
      expect(library.games).toHaveLength(3);

      await backend.deleteGameCollection(c.id);
      library = await backend.load();
      expect(library.gameCollections.map((x) => x.id)).toEqual([kept.collection.id]);
      expect(library.games.map((g) => g.id)).toEqual([kept.games[0].id]);
    });
  });
});

describe('access rules', () => {
  const alice = () => `alice-${++account}`;

  it('shows a second account nothing, and lets it change nothing', async () => {
    const aliceId = alice();
    const mine = restBackend(pgRest(db, aliceId), aliceId);
    const malloryId = `mallory-${account}`;
    const theirs = restBackend(pgRest(db, malloryId), malloryId);

    const c = collection();
    await mine.createCollections([c]);
    const [p] = await mine.importPuzzles([puzzle(c.id, 0)]);
    const r = run(c.id, [p.id]);
    await mine.saveRun(r);
    const a = attempt(p.id, { runId: r.id });
    await mine.recordAttempts([a]);

    const g = gameCollection();
    await mine.createGameCollections([g]);
    const game = newGame(g.id, 0);
    await mine.addGames([game]);
    const before = await mine.load();

    expect(await theirs.load()).toEqual(emptyLibrary());

    await theirs.renameCollection(c.id, 'Taken');
    await theirs.setComment(p.id, 'defaced');
    await theirs.deletePuzzle(p.id);
    await theirs.deleteRun(r.id);
    await theirs.deleteCollection(c.id);
    await theirs.resetProgress();
    await theirs.renameGameCollection(g.id, 'Taken');
    await theirs.updateGame(game.id, { pgn: 'defaced', orientation: 'b' });
    await theirs.deleteGames([game.id]);
    await theirs.deleteGameCollection(g.id);
    expect(await mine.load()).toEqual(before);
  });

  it('refuses rows pointing at another account’s rows', async () => {
    const aliceId = alice();
    const mine = restBackend(pgRest(db, aliceId), aliceId);
    const malloryId = `mallory-${account}`;
    const theirs = restBackend(pgRest(db, malloryId), malloryId);

    const c = collection();
    await mine.createCollections([c]);
    const [p] = await mine.importPuzzles([puzzle(c.id, 0)]);

    // Into Alice's collection: the key includes user_id, so it cannot match.
    await expect(theirs.importPuzzles([puzzle(c.id, 1)])).rejects.toThrow();
    const g = gameCollection();
    await mine.createGameCollections([g]);
    await expect(theirs.addGames([newGame(g.id, 0)])).rejects.toThrow();
    // Nor can a game of Mallory's be moved into it.
    const own = gameCollection();
    await theirs.createGameCollections([own]);
    const game = newGame(own.id, 0);
    await theirs.addGames([game]);
    await expect(
      theirs.placeGames([{ id: game.id, collectionId: g.id, position: 0 }]),
    ).rejects.toThrow();
    // On Alice's puzzle: invisible to Mallory, so dropped as deleted.
    await theirs.recordAttempts([attempt(p.id)]);
    expect((await mine.load()).attempts).toEqual([]);
    // And a raw insert that skips that check still fails on the key.
    await expect(
      asUser(db, malloryId, (q) =>
        q(
          `insert into public.attempts (id, puzzle_id, result, played_at)
             values (gen_random_uuid(), $1, 'solved', now())`,
          [p.id],
        ),
      ),
    ).rejects.toThrow();
  });

  it('refuses rows written in another account’s name', async () => {
    const aliceId = alice();
    await expect(
      asUser(db, `mallory-${account}`, (q) =>
        q(`insert into public.collections (id, user_id, name) values (gen_random_uuid(), $1, 'x')`, [
          aliceId,
        ]),
      ),
    ).rejects.toThrow(/row-level security/);
  });

  it('never changes a run or an attempt once stored', async () => {
    const aliceId = alice();
    const mine = restBackend(pgRest(db, aliceId), aliceId);
    const c = collection();
    await mine.createCollections([c]);
    const [p] = await mine.importPuzzles([puzzle(c.id, 0)]);
    await mine.saveRun(run(c.id, [p.id]));
    await mine.recordAttempts([attempt(p.id)]);

    for (const sql of [
      `update public.runs set mode = 'ordered'`,
      `update public.attempts set result = 'failed'`,
      `update public.collections set created_at = now()`,
      `update public.game_collections set created_at = now()`,
      `update public.games set added_at = now()`,
    ]) {
      await expect(asUser(db, aliceId, (q) => q(sql))).rejects.toThrow(/permission denied/);
    }
  });
});
