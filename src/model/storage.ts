import { get, set } from 'idb-keyval';
import { parseUci } from './move';
import type { Uci } from './move';
import { parsePlacement } from './puzzle';
import type { Collection, Placement, Progress, Puzzle, PuzzleStatus } from './puzzle';
import { TABLES, emptyMeta } from './rows';
import type { SyncMeta } from './rows';
import type { SessionState } from './session';
import { emptyState } from './state';
import type { AppState } from './state';

const KEY = 'motif:state:v1';

export async function loadState(): Promise<AppState> {
  try {
    const raw = await get<unknown>(KEY);
    if (!raw) return emptyState();
    return parseState(raw);
  } catch {
    // A corrupt or unreadable store must not brick the app. Worst case the
    // puzzles are re-imported, which is cheap; that is why export exists.
    return emptyState();
  }
}

export async function saveState(state: AppState): Promise<void> {
  await set(KEY, state);
}

/**
 * Ask the browser to exempt this origin from storage eviction.
 *
 * iOS clears script-writable storage after about seven days of disuse for
 * sites that are not installed to the home screen. This is a request, not a
 * guarantee, and it is why `exportState` exists as well: puzzles can always be
 * re-imported, but solve history cannot.
 */
export async function requestPersistence(): Promise<boolean> {
  if (!navigator.storage?.persist) return false;
  try {
    if (await navigator.storage.persisted()) return true;
    return await navigator.storage.persist();
  } catch {
    return false;
  }
}

/**
 * The library as a backup file.
 *
 * Without its sync record: that describes what this device last agreed with
 * one account's server, and restoring it anywhere else — another device,
 * another account, a later date — would make the next sync read every
 * difference as a deletion.
 */
export function exportState(state: AppState): string {
  const { sync: _sync, ...library } = state;
  return JSON.stringify(library, null, 2);
}

/**
 * Validates an unknown blob into AppState.
 *
 * Lenient about missing optional fields and strict about structure: this is the
 * entry point for hand-edited files and older exports, and silently accepting a
 * malformed puzzle would corrupt the store rather than fail loudly. Anything
 * unparseable is dropped rather than throwing the whole file away — losing one
 * puzzle beats losing a library.
 */
export function parseState(raw: unknown): AppState {
  if (typeof raw !== 'object' || raw === null) throw new Error('Not an object');
  const obj = raw as Record<string, unknown>;

  const puzzles: Record<string, Puzzle> = {};
  if (typeof obj.puzzles === 'object' && obj.puzzles !== null) {
    for (const [id, value] of Object.entries(obj.puzzles as Record<string, unknown>)) {
      const puzzle = parsePuzzle(id, value);
      if (puzzle) puzzles[id] = puzzle;
    }
  }

  const collections: Collection[] = [];
  if (Array.isArray(obj.collections)) {
    for (const value of obj.collections) {
      const collection = value as Record<string, unknown>;
      if (typeof collection?.id !== 'string' || typeof collection?.name !== 'string') continue;
      const puzzleIds = Array.isArray(collection.puzzleIds)
        ? collection.puzzleIds.filter(
            (id): id is string => typeof id === 'string' && Boolean(puzzles[id]),
          )
        : [];
      collections.push({
        id: collection.id,
        name: collection.name,
        createdAt: typeof collection.createdAt === 'number' ? collection.createdAt : Date.now(),
        puzzleIds,
      });
    }
  }

  const progress: Record<string, Progress> = {};
  if (typeof obj.progress === 'object' && obj.progress !== null) {
    for (const [id, value] of Object.entries(obj.progress as Record<string, unknown>)) {
      if (!puzzles[id]) continue;
      const entry = value as Record<string, unknown>;
      const status = entry?.status;
      if (status !== 'solved' && status !== 'failed' && status !== 'unseen') continue;
      progress[id] = {
        puzzleId: id,
        status: status as PuzzleStatus,
        attempts: typeof entry.attempts === 'number' ? entry.attempts : 0,
        mistakes: typeof entry.mistakes === 'number' ? entry.mistakes : 0,
        lastAttemptAt: typeof entry.lastAttemptAt === 'number' ? entry.lastAttemptAt : undefined,
        firstSolvedAt: typeof entry.firstSolvedAt === 'number' ? entry.firstSolvedAt : undefined,
      };
    }
  }

  const sessions: Record<string, SessionState> = {};
  if (typeof obj.sessions === 'object' && obj.sessions !== null) {
    for (const [key, value] of Object.entries(obj.sessions as Record<string, unknown>)) {
      const session = value as SessionState;
      if (!session || !Array.isArray(session.queue)) continue;
      // A session whose puzzles have all gone is not worth resuming into.
      const queue = session.queue.filter((id) => Boolean(puzzles[id]));
      if (!queue.length) continue;
      sessions[key] = { ...session, queue };
    }
  }

  // Must round-trip: the marker is what stops a sync from restoring history the
  // user cleared, so losing it on reload would undo the reset at the next merge.
  const progressResetAt =
    typeof obj.progressResetAt === 'number' ? obj.progressResetAt : undefined;

  const state: AppState = { version: 1, puzzles, collections, progress, sessions, progressResetAt };
  const sync = parseSyncMeta(obj.sync);
  if (sync) state.sync = sync;
  return state;
}

/**
 * The sync record, checked for shape only.
 *
 * It is written by this app and never by hand, so the rows inside are trusted.
 * Anything malformed is dropped whole, which is safe: with no record the next
 * sync starts from nothing and merges by union, as a new device would.
 */
function parseSyncMeta(raw: unknown): SyncMeta | undefined {
  if (typeof raw !== 'object' || raw === null) return undefined;
  const meta = raw as Record<string, unknown>;
  if (typeof meta.userId !== 'string') return undefined;
  if (typeof meta.cursors !== 'object' || meta.cursors === null) return undefined;
  if (typeof meta.base !== 'object' || meta.base === null) return undefined;

  const fresh = emptyMeta(meta.userId);
  const cursors = meta.cursors as Record<string, unknown>;
  const base = meta.base as Record<string, unknown>;
  for (const table of TABLES) {
    const cursor = cursors[table];
    const rows = base[table];
    if (typeof cursor !== 'number' || typeof rows !== 'object' || rows === null) return undefined;
    fresh.cursors[table] = cursor;
    (fresh.base as unknown as Record<string, unknown>)[table] = rows;
  }
  fresh.legacyDone = meta.legacyDone === true;
  return fresh;
}

/**
 * A stored placement, from an export or from a hand-edited file.
 *
 * Exports carry the model's object form; a file edited by hand is likelier to
 * carry the written one it was imported with, so both are read.
 */
function parseStoredPlacement(value: unknown): Placement | undefined {
  if (typeof value === 'string') return parsePlacement(value) ?? undefined;
  if (typeof value !== 'object' || value === null) return undefined;
  const raw = value as Record<string, unknown>;
  if (typeof raw.color !== 'string' || typeof raw.type !== 'string') return undefined;
  if (typeof raw.square !== 'string') return undefined;
  return parsePlacement(`${raw.color}${raw.type}${raw.square}`) ?? undefined;
}

function parsePuzzle(id: string, value: unknown): Puzzle | null {
  const raw = value as Record<string, unknown>;
  if (typeof raw?.fen !== 'string') return null;
  if (!Array.isArray(raw.solutions) && raw.solutions !== undefined) return null;

  const solutions: Uci[][] = [];
  for (const line of raw.solutions ?? []) {
    if (!Array.isArray(line)) return null;
    const moves: Uci[] = [];
    for (const move of line) {
      const parsed = typeof move === 'string' ? parseUci(move) : null;
      if (!parsed) return null;
      moves.push(parsed);
    }
    if (moves.length) solutions.push(moves);
  }

  // A missing-piece puzzle is answered by its placement and has no lines, so
  // "no solutions" only condemns a puzzle that has no placement either.
  const addPiece = parseStoredPlacement(raw.addPiece);
  if (!solutions.length && !addPiece) return null;

  const setupMove = typeof raw.setupMove === 'string' ? parseUci(raw.setupMove) : null;

  return {
    id,
    fen: raw.fen,
    setupMove: setupMove ?? undefined,
    solutions,
    addPiece,
    tags: Array.isArray(raw.tags) ? raw.tags.filter((t): t is string => typeof t === 'string') : [],
    comment: typeof raw.comment === 'string' ? raw.comment : undefined,
    sourceId: typeof raw.sourceId === 'string' ? raw.sourceId : undefined,
    rating: typeof raw.rating === 'number' ? raw.rating : undefined,
    addedAt: typeof raw.addedAt === 'number' ? raw.addedAt : Date.now(),
  };
}
