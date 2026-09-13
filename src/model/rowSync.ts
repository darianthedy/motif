import { parseUci } from './move';
import { parsePlacement } from './puzzle';
import type { Placement, PuzzleStatus } from './puzzle';
import {
  PUSH_ORDER,
  TABLES,
  applyReturned,
  diff,
  emptyMeta,
  fromRows,
  hasChanges,
  integrate,
  keyOf,
  normalize,
  toRows,
} from './rows';
import type {
  CollectionRow,
  MembershipRow,
  OutgoingRow,
  ProgressRow,
  PuzzleRow,
  RemoteRow,
  RemoteRows,
  RowOf,
  RowSet,
  SessionRow,
  SettingsRow,
  SyncMeta,
  TableName,
} from './rows';
import type { SessionState } from './session';
import type { AppState } from './state';
import { parseState } from './storage';
import { mergeStates } from './sync';

/**
 * Row-by-row sync: pull what changed, merge, push what differs.
 *
 * Independent of how rows travel. Production talks to Neon's Data API
 * (neon.ts); the tests talk to a real Postgres running in-process, with the
 * same schema and triggers, which is how the conflict rules on both sides are
 * tested together rather than each against an assumption about the other.
 */

export type WireRow = Record<string, unknown>;

export interface Transport {
  /** Rows with a revision above `after`, lowest first, at most `limit`. */
  pull(table: TableName, after: number, limit: number): Promise<WireRow[]>;
  /** Insert-or-update on the primary key; returns the rows as stored. */
  upsert(table: TableName, rows: WireRow[], conflict: readonly string[]): Promise<WireRow[]>;
  /** The pre-rows single-blob library, if this account still has one. */
  fetchLegacy(): Promise<unknown | null>;
  deleteLegacy(): Promise<void>;
}

/**
 * A push collided with a live row the device has not seen yet: the same puzzle
 * or collection name, created on another device since the last pull. Not a
 * failure — pulling again brings the other row in, the merge folds the two
 * together, and the retry goes through.
 */
export class RowConflict extends Error {
  constructor() {
    super('Another device added the same thing at the same time');
    this.name = 'RowConflict';
  }
}

export const PAGE_SIZE = 1000;
const PUSH_CHUNK = 500;

export const PRIMARY_KEYS: Record<TableName, readonly string[]> = {
  library_settings: ['user_id'],
  puzzles: ['user_id', 'id'],
  collections: ['user_id', 'id'],
  collection_puzzles: ['user_id', 'collection_id', 'puzzle_id'],
  progress: ['user_id', 'puzzle_id'],
  sessions: ['user_id', 'key'],
};

// ---------------------------------------------------------------------------
// Wire format
// ---------------------------------------------------------------------------

function toWire<T extends TableName>(
  table: T,
  { row, deletedAt }: OutgoingRow<T>,
  userId: string,
): WireRow {
  switch (table) {
    case 'library_settings': {
      const r = row as SettingsRow;
      return { user_id: userId, progress_reset_at: r.progressResetAt };
    }
    case 'puzzles': {
      const r = row as PuzzleRow;
      return {
        user_id: userId,
        id: r.id,
        content_key: r.contentKey,
        fen: r.fen,
        setup_move: r.setupMove,
        solutions: r.solutions,
        add_piece: r.addPiece,
        tags: r.tags,
        comment: r.comment,
        source_id: r.sourceId,
        rating: r.rating,
        added_at: r.addedAt,
        deleted_at: deletedAt,
      };
    }
    case 'collections': {
      const r = row as CollectionRow;
      return {
        user_id: userId,
        id: r.id,
        name: r.name,
        created_at: r.createdAt,
        deleted_at: deletedAt,
      };
    }
    case 'collection_puzzles': {
      const r = row as MembershipRow;
      return {
        user_id: userId,
        collection_id: r.collectionId,
        puzzle_id: r.puzzleId,
        position: r.position,
        deleted_at: deletedAt,
      };
    }
    case 'progress': {
      const r = row as ProgressRow;
      return {
        user_id: userId,
        puzzle_id: r.puzzleId,
        status: r.status,
        attempts: r.attempts,
        mistakes: r.mistakes,
        last_attempt_at: r.lastAttemptAt,
        first_solved_at: r.firstSolvedAt,
        deleted_at: deletedAt,
      };
    }
    case 'sessions': {
      const r = row as SessionRow;
      return {
        user_id: userId,
        key: r.key,
        session: r.session,
        last_active_at: r.lastActiveAt,
        deleted_at: deletedAt,
      };
    }
  }
  throw new Error(`Unknown table ${table as string}`);
}

const str = (value: unknown): string | null => (typeof value === 'string' ? value : null);

/** Postgres bigint may arrive as a string or a BigInt, depending on the driver. */
const num = (value: unknown): number | null => {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'bigint') return Number(value);
  if (typeof value === 'string' && value.trim() !== '' && Number.isFinite(Number(value))) {
    return Number(value);
  }
  return null;
};

function placementFrom(value: unknown): Placement | null {
  if (typeof value !== 'object' || value === null) return null;
  const raw = value as Record<string, unknown>;
  if (typeof raw.color !== 'string' || typeof raw.type !== 'string') return null;
  if (typeof raw.square !== 'string') return null;
  return parsePlacement(`${raw.color}${raw.type}${raw.square}`);
}

/**
 * A stored row back into the app's shape.
 *
 * Parsed rather than trusted, for the same reason the local store is: a row can
 * be hand-edited in the console or predate a change here. A row that does not
 * parse is skipped — treated as if it had never been received — which costs one
 * puzzle rather than the whole sync.
 */
function fromWire<T extends TableName>(table: T, wire: WireRow): RemoteRow<T> | null {
  const deletedAt = num(wire.deleted_at);
  const revision = num(wire.revision) ?? 0;
  let row: RowOf<TableName> | null = null;

  switch (table as TableName) {
    case 'library_settings':
      row = { progressResetAt: num(wire.progress_reset_at) } satisfies SettingsRow;
      break;
    case 'puzzles': {
      const id = str(wire.id);
      const fen = str(wire.fen);
      const key = str(wire.content_key);
      const addedAt = num(wire.added_at);
      if (!id || !fen || !key || addedAt === null || !Array.isArray(wire.solutions)) break;
      const solutions: string[][] = [];
      let valid = true;
      for (const line of wire.solutions) {
        if (!Array.isArray(line) || !line.every((move) => typeof move === 'string' && parseUci(move))) {
          valid = false;
          break;
        }
        solutions.push(line as string[]);
      }
      if (!valid) break;
      row = {
        id,
        contentKey: key,
        fen,
        setupMove: str(wire.setup_move),
        solutions,
        addPiece: placementFrom(wire.add_piece),
        tags: Array.isArray(wire.tags)
          ? wire.tags.filter((tag): tag is string => typeof tag === 'string')
          : [],
        comment: str(wire.comment),
        sourceId: str(wire.source_id),
        rating: num(wire.rating),
        addedAt,
      } satisfies PuzzleRow;
      break;
    }
    case 'collections': {
      const id = str(wire.id);
      const name = str(wire.name);
      const createdAt = num(wire.created_at);
      if (!id || name === null || createdAt === null) break;
      row = { id, name, createdAt } satisfies CollectionRow;
      break;
    }
    case 'collection_puzzles': {
      const collectionId = str(wire.collection_id);
      const puzzleId = str(wire.puzzle_id);
      const position = num(wire.position);
      if (!collectionId || !puzzleId || position === null) break;
      row = { collectionId, puzzleId, position } satisfies MembershipRow;
      break;
    }
    case 'progress': {
      const puzzleId = str(wire.puzzle_id);
      const status = wire.status;
      if (!puzzleId || (status !== 'solved' && status !== 'failed' && status !== 'unseen')) break;
      row = {
        puzzleId,
        status: status as PuzzleStatus,
        attempts: num(wire.attempts) ?? 0,
        mistakes: num(wire.mistakes) ?? 0,
        lastAttemptAt: num(wire.last_attempt_at),
        firstSolvedAt: num(wire.first_solved_at),
      } satisfies ProgressRow;
      break;
    }
    case 'sessions': {
      const key = str(wire.key);
      const lastActiveAt = num(wire.last_active_at);
      const session = wire.session as SessionState | null;
      if (!key || lastActiveAt === null || !session || !Array.isArray(session.queue)) break;
      row = { key, session, lastActiveAt } satisfies SessionRow;
      break;
    }
  }

  if (!row) return null;
  return { key: keyOf(table, row as RowOf<T>), row: row as RowOf<T>, deletedAt, revision };
}

function parseRows<T extends TableName>(table: T, wire: WireRow[]): RemoteRow<T>[] {
  return wire.map((w) => fromWire(table, w)).filter((r): r is RemoteRow<T> => r !== null);
}

// ---------------------------------------------------------------------------
// Pull and push
// ---------------------------------------------------------------------------

async function pullTable<T extends TableName>(
  transport: Transport,
  table: T,
  after: number,
): Promise<{ rows: RemoteRow<T>[]; cursor: number }> {
  const rows: RemoteRow<T>[] = [];
  let cursor = after;
  for (;;) {
    const page = await transport.pull(table, cursor, PAGE_SIZE);
    for (const wire of page) cursor = Math.max(cursor, num(wire.revision) ?? cursor);
    rows.push(...parseRows(table, page));
    // A short page is the last one. If the server caps pages below PAGE_SIZE
    // this stops early, which only defers the rest to the next sync: the
    // cursor has advanced exactly as far as what was seen.
    if (page.length < PAGE_SIZE) break;
  }
  return { rows, cursor };
}

async function pullAll(
  transport: Transport,
  cursors: SyncMeta['cursors'],
): Promise<{ rows: RemoteRows; cursors: SyncMeta['cursors']; any: boolean }> {
  const results = await Promise.all(
    TABLES.map((table) => pullTable(transport, table, cursors[table] ?? 0)),
  );
  const rows = {} as RemoteRows;
  const next = { ...cursors };
  let any = false;
  TABLES.forEach((table, i) => {
    (rows as Record<TableName, RemoteRow[]>)[table] = results[i].rows;
    next[table] = results[i].cursor;
    if (results[i].rows.length) any = true;
  });
  return { rows, cursors: next, any };
}

async function pushTable<T extends TableName>(
  transport: Transport,
  table: T,
  outgoing: OutgoingRow<T>[],
  userId: string,
): Promise<RemoteRow<T>[]> {
  const returned: RemoteRow<T>[] = [];
  for (let i = 0; i < outgoing.length; i += PUSH_CHUNK) {
    const chunk = outgoing.slice(i, i + PUSH_CHUNK).map((o) => toWire(table, o, userId));
    returned.push(...parseRows(table, await transport.upsert(table, chunk, PRIMARY_KEYS[table])));
  }
  return returned;
}

/** Pushes rounds until nothing differs; the server's answers can cascade. */
const MAX_PUSH_ROUNDS = 3;
const MAX_CONFLICT_RETRIES = 3;

/**
 * One full sync of `local` with the account's rows. Returns the library to
 * adopt, carrying its updated sync record.
 *
 * Returns `local` itself when nothing moved in either direction, so an idle
 * sync does not churn state identity and trigger another one.
 */
export async function syncRows(
  local: AppState,
  userId: string,
  transport: Transport,
  now: () => number = Date.now,
): Promise<AppState> {
  const meta: SyncMeta = local.sync?.userId === userId ? local.sync : emptyMeta(userId);

  let data = local;
  let legacyFound = false;
  if (!meta.legacyDone) {
    const blob = await transport.fetchLegacy();
    if (blob) {
      // A one-off union with the old blob. The blob has no deletion markers,
      // so a union is all it can support — which is exactly why it is going.
      data = mergeStates(data, parseState(blob));
      legacyFound = true;
    }
  }

  let base: RowSet = meta.base;
  let rows = normalize(toRows(data, base), base);
  let cursors = meta.cursors;
  let moved = legacyFound || !meta.legacyDone;

  const pull = async () => {
    const pulled = await pullAll(transport, cursors);
    if (pulled.any) moved = true;
    cursors = pulled.cursors;
    ({ rows, base } = integrate(rows, base, pulled.rows));
    rows = normalize(rows, base);
  };

  await pull();

  for (let attempt = 0; ; attempt++) {
    try {
      for (let round = 0; round < MAX_PUSH_ROUNDS; round++) {
        const changes = diff(rows, base, now());
        if (!hasChanges(changes)) break;
        moved = true;
        for (const table of PUSH_ORDER) {
          const outgoing = changes[table];
          if (!outgoing.length) continue;
          const returned = await pushTable(transport, table, outgoing, userId);
          ({ rows, base } = applyReturned(rows, base, { [table]: returned }));
        }
        rows = normalize(rows, base);
      }
      break;
    } catch (error) {
      if (!(error instanceof RowConflict) || attempt >= MAX_CONFLICT_RETRIES - 1) throw error;
      await pull();
    }
  }

  // Only once the rows are safely stored: deleting first would lose the
  // library if the push had failed.
  if (legacyFound) await transport.deleteLegacy();

  if (!moved) return local;

  const state = fromRows(rows);
  state.sync = { userId, cursors, base, legacyDone: true };
  return state;
}
