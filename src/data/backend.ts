import { parseUci } from '../model/move';
import { contentKey, parsePlacement, placementText } from '../model/puzzle';
import type { Collection, Puzzle } from '../model/puzzle';
import type { SessionMode } from '../model/session';

/**
 * The account's library, as the database holds it.
 *
 * One `Backend` interface and two implementations: `restBackend`, which talks
 * to Neon's Data API (or anything else that speaks the same subset of
 * PostgREST), and `memoryBackend`, which keeps everything in a plain object
 * for unit tests, the e2e run and a dev mode with no database. Both obey the
 * same rules, and `backend.test.ts` runs one suite against each.
 */

/**
 * A puzzle on its way in: the database assigns the id and the time. The flag
 * is left out so an import never clears one.
 */
export type NewPuzzle = Omit<Puzzle, 'id' | 'addedAt' | 'flagged'>;

/** A collection id, or one of the two scopes that span the whole library. */
export type RunScope = string;
export const SCOPE_ALL = 'all';
export const SCOPE_REVIEW = 'review';

/**
 * A run through a set of puzzles: only what never changes after it starts.
 * Where it has got to is worked out from its attempts (see derive.ts).
 */
export interface Run {
  id: string;
  scope: RunScope;
  mode: SessionMode;
  queue: string[];
  startedAt: number;
}

export type AttemptResult = 'solved' | 'failed' | 'skipped';

export interface Attempt {
  /** Generated on the device, so uploading it twice stores it once. */
  id: string;
  puzzleId: string;
  /** Null once the run it was played in is gone. */
  runId: string | null;
  result: AttemptResult;
  mistakes: number;
  hinted: boolean;
  playedAt: number;
}

export type { Collection, Puzzle };

export interface Library {
  collections: Collection[];
  puzzles: Puzzle[];
  runs: Run[];
  attempts: Attempt[];
}

export function emptyLibrary(): Library {
  return { collections: [], puzzles: [], runs: [], attempts: [] };
}

export interface Backend {
  /** Everything the signed-in account has. */
  load(): Promise<Library>;

  /** The ids are set by the caller, so puzzles can be imported into them straight away. */
  createCollections(collections: Collection[]): Promise<void>;
  renameCollection(id: string, name: string): Promise<void>;
  /** Takes its puzzles, their attempts and the collection's run with it. */
  deleteCollection(id: string): Promise<void>;

  /**
   * Adds puzzles, or updates the ones a collection already has with the same
   * content. An update takes everything but the id and the time added from
   * the file, so the file wins over an in-app comment edit. Returns the
   * puzzles as stored.
   */
  importPuzzles(puzzles: NewPuzzle[]): Promise<Puzzle[]>;
  /** Empty text clears the comment. */
  setComment(puzzleId: string, comment: string): Promise<void>;
  /** Marks a puzzle as needing a look, or clears the mark. */
  setFlagged(puzzleId: string, flagged: boolean): Promise<void>;
  /** Takes its attempts with it. */
  deletePuzzle(id: string): Promise<void>;

  /**
   * Stores a run, replacing an older one in the same scope. A newer run
   * already in the scope wins, and this one is dropped. Storing the same run
   * twice does nothing.
   */
  saveRun(run: Run): Promise<void>;
  /** Its attempts stay, without a run. */
  deleteRun(id: string): Promise<void>;

  /**
   * Stores attempts; one already stored is left as it is. An attempt on a
   * puzzle that no longer exists is dropped, and one whose run no longer
   * exists is kept without it.
   */
  recordAttempts(attempts: Attempt[]): Promise<void>;
  /** Deletes every attempt and run. */
  resetProgress(): Promise<void>;
}

/** Empty text means no comment, rather than a stored "". */
function cleanComment(comment: string): string | undefined {
  return comment.trim() || undefined;
}

/**
 * The last of each puzzle with the same content in the same collection, in
 * order. Two in one upsert would be the same row updated twice, which
 * Postgres refuses.
 */
function distinctPuzzles(puzzles: NewPuzzle[]): NewPuzzle[] {
  const byKey = new Map<string, NewPuzzle>();
  for (const puzzle of puzzles) {
    const key = `${puzzle.collectionId}/${contentKey(puzzle)}`;
    byKey.delete(key);
    byKey.set(key, puzzle);
  }
  return [...byKey.values()];
}

// ---------------------------------------------------------------------------
// PostgREST
// ---------------------------------------------------------------------------

export type Row = Record<string, unknown>;

export type Filter =
  | { column: string; eq: unknown }
  | { column: string; in: unknown[] }
  | { column: string; lt: unknown };

export interface UpsertOptions {
  /** The unique columns that decide whether a row is already there. */
  onConflict: string[];
  /** Leave a row that is already there as it is, rather than updating it. */
  ignoreDuplicates?: boolean;
}

/**
 * The subset of PostgREST the backend uses. Neon's client provides it in
 * production; the tests provide it over SQL, against the real schema.
 */
export interface Rest {
  /** Every matching row, however many pages that takes. */
  select(table: string, filters?: Filter[]): Promise<Row[]>;
  /** Rows absent from a row are left to their column default. Returns the rows as stored. */
  insert(table: string, rows: Row[], upsert?: UpsertOptions): Promise<Row[]>;
  update(table: string, patch: Row, filters: Filter[]): Promise<void>;
  delete(table: string, filters: Filter[]): Promise<void>;
}

/** Keeps request bodies and `in` filters to a sensible size. */
const CHUNK = 200;

function chunks<T>(items: T[], size = CHUNK): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

const iso = (ms: number) => new Date(ms).toISOString();

const time = (value: unknown): number => {
  const ms = typeof value === 'string' ? Date.parse(value) : NaN;
  if (Number.isNaN(ms)) throw new Error(`Not a timestamp: ${String(value)}`);
  return ms;
};

const optional = <T>(value: T | null | undefined): T | undefined => value ?? undefined;

function puzzleFrom(row: Row): Puzzle {
  const solutions = (row.solutions as string[][]).map((line) =>
    line.map((move) => {
      const parsed = parseUci(move);
      if (!parsed) throw new Error(`Not a UCI move: ${move}`);
      return parsed;
    }),
  );
  return {
    id: row.id as string,
    collectionId: row.collection_id as string,
    position: row.position as number,
    fen: row.fen as string,
    solutions,
    addPiece: optional(parsePlacement((row.add_piece as string | null) ?? '')),
    tags: (row.tags as string[]) ?? [],
    comment: optional(row.comment as string | null),
    sourceId: optional(row.source_id as string | null),
    rating: optional(row.rating as number | null),
    flagged: row.flagged === true || undefined,
    addedAt: time(row.added_at),
  };
}

function puzzleRow(puzzle: NewPuzzle): Row {
  return {
    collection_id: puzzle.collectionId,
    position: puzzle.position,
    content_key: contentKey(puzzle),
    fen: puzzle.fen,
    solutions: puzzle.solutions,
    add_piece: puzzle.addPiece ? placementText(puzzle.addPiece) : null,
    tags: puzzle.tags,
    comment: puzzle.comment ?? null,
    source_id: puzzle.sourceId ?? null,
    rating: puzzle.rating ?? null,
  };
}

function attemptRow(attempt: Attempt): Row {
  return {
    id: attempt.id,
    puzzle_id: attempt.puzzleId,
    run_id: attempt.runId,
    result: attempt.result,
    mistakes: attempt.mistakes,
    hinted: attempt.hinted,
    played_at: iso(attempt.playedAt),
  };
}

/** Of `ids`, the ones `table` has. */
async function existing(rest: Rest, table: string, ids: string[]): Promise<Set<string>> {
  const found = new Set<string>();
  for (const chunk of chunks([...new Set(ids)])) {
    const rows = await rest.select(table, [{ column: 'id', in: chunk }]);
    for (const row of rows) found.add(row.id as string);
  }
  return found;
}

/** `userId` is the signed-in account, whose rows RLS limits `rest` to. */
export function restBackend(rest: Rest, userId: string): Backend {
  return {
    async load() {
      const [collections, puzzles, runs, attempts] = await Promise.all([
        rest.select('collections'),
        rest.select('puzzles'),
        rest.select('runs'),
        rest.select('attempts'),
      ]);
      return {
        collections: collections.map((row) => ({
          id: row.id as string,
          name: row.name as string,
          createdAt: time(row.created_at),
        })),
        puzzles: puzzles.map(puzzleFrom),
        runs: runs.map((row) => ({
          id: row.id as string,
          scope: row.scope as string,
          mode: row.mode as SessionMode,
          queue: row.queue as string[],
          startedAt: time(row.started_at),
        })),
        attempts: attempts.map((row) => ({
          id: row.id as string,
          puzzleId: row.puzzle_id as string,
          runId: (row.run_id as string | null) ?? null,
          result: row.result as AttemptResult,
          mistakes: row.mistakes as number,
          hinted: row.hinted as boolean,
          playedAt: time(row.played_at),
        })),
      };
    },

    async createCollections(collections) {
      if (!collections.length) return;
      await rest.insert(
        'collections',
        collections.map((c) => ({ id: c.id, name: c.name, created_at: iso(c.createdAt) })),
      );
    },

    async renameCollection(id, name) {
      await rest.update('collections', { name }, [{ column: 'id', eq: id }]);
    },

    async deleteCollection(id) {
      // A run is tied to its collection by scope only, not by a key, so it has
      // to be deleted on its own.
      await rest.delete('runs', [{ column: 'scope', eq: id }]);
      await rest.delete('collections', [{ column: 'id', eq: id }]);
    },

    async importPuzzles(puzzles) {
      const stored: Puzzle[] = [];
      for (const chunk of chunks(distinctPuzzles(puzzles))) {
        const rows = await rest.insert('puzzles', chunk.map(puzzleRow), {
          onConflict: ['collection_id', 'content_key'],
        });
        stored.push(...rows.map(puzzleFrom));
      }
      return stored;
    },

    async setComment(puzzleId, comment) {
      await rest.update('puzzles', { comment: cleanComment(comment) ?? null }, [
        { column: 'id', eq: puzzleId },
      ]);
    },

    async setFlagged(puzzleId, flagged) {
      await rest.update('puzzles', { flagged }, [{ column: 'id', eq: puzzleId }]);
    },

    async deletePuzzle(id) {
      await rest.delete('puzzles', [{ column: 'id', eq: id }]);
    },

    async saveRun(run) {
      await rest.delete('runs', [
        { column: 'scope', eq: run.scope },
        { column: 'started_at', lt: iso(run.startedAt) },
      ]);
      await rest.insert(
        'runs',
        [
          {
            id: run.id,
            scope: run.scope,
            mode: run.mode,
            queue: run.queue,
            started_at: iso(run.startedAt),
          },
        ],
        { onConflict: ['user_id', 'scope'], ignoreDuplicates: true },
      );
    },

    async deleteRun(id) {
      await rest.delete('runs', [{ column: 'id', eq: id }]);
    },

    async recordAttempts(attempts) {
      if (!attempts.length) return;
      // Checked here rather than left to the foreign keys, which would fail
      // the whole upload over one puzzle deleted on another device. Something
      // deleted between this check and the insert fails it once, and the
      // outbox's next try gets past it.
      const puzzles = await existing(rest, 'puzzles', attempts.map((a) => a.puzzleId));
      const runIds = attempts.flatMap((a) => (a.runId ? [a.runId] : []));
      const runs = runIds.length ? await existing(rest, 'runs', runIds) : new Set<string>();
      const rows = attempts
        .filter((a) => puzzles.has(a.puzzleId))
        .map((a) => attemptRow(a.runId && !runs.has(a.runId) ? { ...a, runId: null } : a));
      for (const chunk of chunks(rows)) {
        await rest.insert('attempts', chunk, { onConflict: ['id'], ignoreDuplicates: true });
      }
    },

    async resetProgress() {
      // RLS would limit an unfiltered DELETE to the account anyway, but a
      // Data API may refuse one outright, and saying whose rows is clearer.
      const own: Filter[] = [{ column: 'user_id', eq: userId }];
      await rest.delete('attempts', own);
      await rest.delete('runs', own);
    },
  };
}

// ---------------------------------------------------------------------------
// In memory
// ---------------------------------------------------------------------------

/**
 * A backend with no database, for unit tests, the e2e run and a dev server
 * without Neon. One account, and data that lasts as long as the page.
 */
export function memoryBackend(initial: Library = emptyLibrary()): Backend & { library: Library } {
  const library = structuredClone(initial);
  const copy = <T>(value: T): T => structuredClone(value);

  return {
    library,

    async load() {
      return copy(library);
    },

    async createCollections(collections) {
      for (const collection of collections) {
        if (library.collections.some((c) => c.id === collection.id)) {
          throw new Error(`Collection ${collection.id} already exists`);
        }
      }
      library.collections.push(...copy(collections));
    },

    async renameCollection(id, name) {
      for (const collection of library.collections) {
        if (collection.id === id) collection.name = name;
      }
    },

    async deleteCollection(id) {
      library.collections = library.collections.filter((c) => c.id !== id);
      library.runs = library.runs.filter((r) => r.scope !== id);
      const gone = new Set(library.puzzles.filter((p) => p.collectionId === id).map((p) => p.id));
      dropPuzzles(gone);
    },

    async importPuzzles(puzzles) {
      const stored: Puzzle[] = [];
      for (const incoming of distinctPuzzles(puzzles)) {
        if (!library.collections.some((c) => c.id === incoming.collectionId)) {
          throw new Error(`No collection ${incoming.collectionId}`);
        }
        const key = contentKey(incoming);
        const index = library.puzzles.findIndex(
          (p) => p.collectionId === incoming.collectionId && contentKey(p) === key,
        );
        const now = Date.now();
        const puzzle: Puzzle =
          index >= 0
            ? {
                ...copy(incoming),
                id: library.puzzles[index].id,
                addedAt: library.puzzles[index].addedAt,
                flagged: library.puzzles[index].flagged,
              }
            : { ...copy(incoming), id: crypto.randomUUID(), addedAt: now };
        if (index >= 0) library.puzzles[index] = puzzle;
        else library.puzzles.push(puzzle);
        stored.push(copy(puzzle));
      }
      return stored;
    },

    async setComment(puzzleId, comment) {
      for (const puzzle of library.puzzles) {
        if (puzzle.id === puzzleId) puzzle.comment = cleanComment(comment);
      }
    },

    async setFlagged(puzzleId, flagged) {
      for (const puzzle of library.puzzles) {
        if (puzzle.id === puzzleId) puzzle.flagged = flagged || undefined;
      }
    },

    async deletePuzzle(id) {
      dropPuzzles(new Set([id]));
    },

    async saveRun(run) {
      const held = library.runs.find((r) => r.scope === run.scope);
      if (held && held.startedAt >= run.startedAt) return;
      if (held) await this.deleteRun(held.id);
      library.runs.push(copy(run));
    },

    async deleteRun(id) {
      library.runs = library.runs.filter((r) => r.id !== id);
      for (const attempt of library.attempts) {
        if (attempt.runId === id) attempt.runId = null;
      }
    },

    async recordAttempts(attempts) {
      const puzzles = new Set(library.puzzles.map((p) => p.id));
      const runs = new Set(library.runs.map((r) => r.id));
      const stored = new Set(library.attempts.map((a) => a.id));
      for (const attempt of attempts) {
        if (stored.has(attempt.id) || !puzzles.has(attempt.puzzleId)) continue;
        stored.add(attempt.id);
        library.attempts.push({
          ...copy(attempt),
          runId: attempt.runId && runs.has(attempt.runId) ? attempt.runId : null,
        });
      }
    },

    async resetProgress() {
      library.attempts = [];
      library.runs = [];
    },
  };

  function dropPuzzles(ids: Set<string>) {
    library.puzzles = library.puzzles.filter((p) => !ids.has(p.id));
    library.attempts = library.attempts.filter((a) => !ids.has(a.puzzleId));
  }
}
