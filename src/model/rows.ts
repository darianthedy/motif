import type { Uci } from './move';
import { contentKey } from './puzzle';
import type { Collection, Placement, Progress, Puzzle, PuzzleStatus } from './puzzle';
import { reconcile } from './session';
import type { SessionState } from './session';
import type { AppState } from './state';

/**
 * The library as database rows, and the rules for reconciling two copies.
 *
 * The app works on `AppState` everywhere — one object, replaced wholesale on
 * every change. The server stores one row per puzzle, collection, membership,
 * progress entry and session (db/0002_rows.neon.sql). This file is the bridge:
 * pure functions from one shape to the other, and a three-way merge between
 * this device's rows, the server's rows, and the *base* — the rows as they
 * stood when the two last agreed.
 *
 * The base is what makes deletion work. Without it, a row missing here is
 * ambiguous: deleted on this device, or never received? With it, "in the base
 * but not here" can only mean deleted here, so it is pushed as a deletion; and
 * "in the base, unchanged here, marked deleted on the server" can only mean
 * deleted elsewhere, so it goes. A plain union — the old blob merge — can do
 * neither, which is why deletions used to come back.
 */

export const TABLES = [
  'library_settings',
  'puzzles',
  'collections',
  'collection_puzzles',
  'progress',
  'sessions',
] as const;

export type TableName = (typeof TABLES)[number];

/**
 * Parents before children, so every foreign key already exists when a row
 * that points at it arrives. Settings go first so the server's reset check
 * sees a reset before the progress it discards.
 */
export const PUSH_ORDER: readonly TableName[] = TABLES;

export interface SettingsRow {
  progressResetAt: number | null;
}

export interface PuzzleRow {
  id: string;
  contentKey: string;
  fen: string;
  setupMove: string | null;
  solutions: string[][];
  addPiece: Placement | null;
  tags: string[];
  comment: string | null;
  sourceId: string | null;
  rating: number | null;
  addedAt: number;
}

export interface CollectionRow {
  id: string;
  name: string;
  createdAt: number;
}

export interface MembershipRow {
  collectionId: string;
  puzzleId: string;
  position: number;
}

export interface ProgressRow {
  puzzleId: string;
  status: PuzzleStatus;
  attempts: number;
  mistakes: number;
  lastAttemptAt: number | null;
  firstSolvedAt: number | null;
}

export interface SessionRow {
  key: string;
  session: SessionState;
  lastActiveAt: number;
}

export interface RowSet {
  library_settings: Record<string, SettingsRow>;
  puzzles: Record<string, PuzzleRow>;
  collections: Record<string, CollectionRow>;
  collection_puzzles: Record<string, MembershipRow>;
  progress: Record<string, ProgressRow>;
  sessions: Record<string, SessionRow>;
}

export type RowOf<T extends TableName> = RowSet[T][string];

/** A row as the server holds it: possibly marked deleted, always versioned. */
export interface RemoteRow<T extends TableName = TableName> {
  key: string;
  row: RowOf<T>;
  deletedAt: number | null;
  revision: number;
}

export type RemoteRows = { [T in TableName]: RemoteRow<T>[] };

/** A row to upsert: the row itself, marked deleted or not. */
export interface OutgoingRow<T extends TableName = TableName> {
  row: RowOf<T>;
  deletedAt: number | null;
}

export type Changes = { [T in TableName]: OutgoingRow<T>[] };

export interface SyncMeta {
  /** The account this record belongs to. Another account starts from nothing. */
  userId: string;
  /** Highest revision seen per table: the next pull asks only for newer rows. */
  cursors: Record<TableName, number>;
  /** The server's live rows as this device last saw them. */
  base: RowSet;
  /** Whether the old single-blob library has been folded in for this account. */
  legacyDone: boolean;
}

/** The settings table has one row per user, so one fixed key locally. */
export const SETTINGS_KEY = 'settings';

export function emptyRows(): RowSet {
  return {
    library_settings: {},
    puzzles: {},
    collections: {},
    collection_puzzles: {},
    progress: {},
    sessions: {},
  };
}

export function emptyMeta(userId: string): SyncMeta {
  const cursors = Object.fromEntries(TABLES.map((table) => [table, 0])) as SyncMeta['cursors'];
  return { userId, cursors, base: emptyRows(), legacyDone: false };
}

export function membershipKey(collectionId: string, puzzleId: string): string {
  // JSON rather than a separator character: ids come from imported files too,
  // and no character is guaranteed absent from a string someone typed.
  return JSON.stringify([collectionId, puzzleId]);
}

export function keyOf<T extends TableName>(table: T, row: RowOf<T>): string {
  switch (table) {
    case 'library_settings':
      return SETTINGS_KEY;
    case 'puzzles':
    case 'collections':
      return (row as PuzzleRow | CollectionRow).id;
    case 'collection_puzzles': {
      const m = row as MembershipRow;
      return membershipKey(m.collectionId, m.puzzleId);
    }
    case 'progress':
      return (row as ProgressRow).puzzleId;
    case 'sessions':
      return (row as SessionRow).key;
  }
  throw new Error(`Unknown table ${table as string}`);
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

/**
 * A stable serialization: keys sorted, undefined dropped.
 *
 * Needed because rows round-trip through jsonb, which reorders object keys —
 * a session read back from the server is the same session with its keys in a
 * different order, and plain JSON.stringify would call every one of them a
 * change and push it again forever.
 */
export function canonical(value: unknown): string {
  return JSON.stringify(value, (_key, inner: unknown) => {
    if (inner === null || typeof inner !== 'object' || Array.isArray(inner)) return inner;
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(inner).sort()) {
      sorted[key] = (inner as Record<string, unknown>)[key];
    }
    return sorted;
  });
}

export function sameRow(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a === undefined || b === undefined) return false;
  return canonical(a) === canonical(b);
}

// ---------------------------------------------------------------------------
// AppState <-> rows
// ---------------------------------------------------------------------------

function puzzleRow(puzzle: Puzzle): PuzzleRow {
  return {
    id: puzzle.id,
    contentKey: contentKey(puzzle),
    fen: puzzle.fen,
    setupMove: puzzle.setupMove ?? null,
    solutions: puzzle.solutions,
    addPiece: puzzle.addPiece ?? null,
    tags: puzzle.tags,
    comment: puzzle.comment ?? null,
    sourceId: puzzle.sourceId ?? null,
    rating: puzzle.rating ?? null,
    addedAt: puzzle.addedAt,
  };
}

function progressRow(entry: Progress): ProgressRow {
  return {
    puzzleId: entry.puzzleId,
    status: entry.status,
    attempts: entry.attempts,
    mistakes: entry.mistakes,
    lastAttemptAt: entry.lastAttemptAt ?? null,
    firstSolvedAt: entry.firstSolvedAt ?? null,
  };
}

/**
 * The library as rows.
 *
 * `base` supplies membership positions. A collection is an ordered list here
 * and a set of positioned rows there; reusing the stored position for every
 * membership the server already has is what keeps deleting one puzzle from
 * renumbering — and re-uploading — every puzzle after it. New memberships are
 * appended past the highest known position, which matches how the app adds
 * them: imports only ever append.
 */
export function toRows(state: AppState, base: RowSet): RowSet {
  const rows = emptyRows();
  rows.library_settings[SETTINGS_KEY] = { progressResetAt: state.progressResetAt ?? null };

  for (const puzzle of Object.values(state.puzzles)) rows.puzzles[puzzle.id] = puzzleRow(puzzle);

  const highest = new Map<string, number>();
  for (const m of Object.values(base.collection_puzzles)) {
    highest.set(m.collectionId, Math.max(highest.get(m.collectionId) ?? 0, m.position));
  }

  for (const collection of state.collections) {
    rows.collections[collection.id] = {
      id: collection.id,
      name: collection.name,
      createdAt: collection.createdAt,
    };
    for (const puzzleId of collection.puzzleIds) {
      const key = membershipKey(collection.id, puzzleId);
      if (rows.collection_puzzles[key]) continue;
      let position = base.collection_puzzles[key]?.position;
      if (position === undefined) {
        position = (highest.get(collection.id) ?? 0) + 1;
        highest.set(collection.id, position);
      }
      rows.collection_puzzles[key] = { collectionId: collection.id, puzzleId, position };
    }
  }

  for (const entry of Object.values(state.progress)) {
    rows.progress[entry.puzzleId] = progressRow(entry);
  }

  for (const [key, session] of Object.entries(state.sessions)) {
    rows.sessions[key] = { key, session, lastActiveAt: session.lastActiveAt };
  }

  return rows;
}

function puzzleFromRow(row: PuzzleRow): Puzzle {
  const puzzle: Puzzle = {
    id: row.id,
    fen: row.fen,
    solutions: row.solutions as Uci[][],
    tags: row.tags,
    addedAt: row.addedAt,
  };
  if (row.setupMove !== null) puzzle.setupMove = row.setupMove as Uci;
  if (row.addPiece !== null) puzzle.addPiece = row.addPiece;
  if (row.comment !== null) puzzle.comment = row.comment;
  if (row.sourceId !== null) puzzle.sourceId = row.sourceId;
  if (row.rating !== null) puzzle.rating = row.rating;
  return puzzle;
}

function progressFromRow(row: ProgressRow): Progress {
  const entry: Progress = {
    puzzleId: row.puzzleId,
    status: row.status,
    attempts: row.attempts,
    mistakes: row.mistakes,
  };
  if (row.lastAttemptAt !== null) entry.lastAttemptAt = row.lastAttemptAt;
  if (row.firstSolvedAt !== null) entry.firstSolvedAt = row.firstSolvedAt;
  return entry;
}

/** The inverse of `toRows`. The sync record is the caller's to attach. */
export function fromRows(rows: RowSet): AppState {
  const puzzles: Record<string, Puzzle> = {};
  for (const row of Object.values(rows.puzzles)) puzzles[row.id] = puzzleFromRow(row);

  const members = new Map<string, MembershipRow[]>();
  for (const m of Object.values(rows.collection_puzzles)) {
    const list = members.get(m.collectionId) ?? [];
    list.push(m);
    members.set(m.collectionId, list);
  }

  const collections: Collection[] = Object.values(rows.collections)
    .sort((a, b) => a.createdAt - b.createdAt || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((row) => ({
      id: row.id,
      name: row.name,
      createdAt: row.createdAt,
      // Ties are possible when two devices append at once; the id breaks them
      // the same way on every device.
      puzzleIds: (members.get(row.id) ?? [])
        .sort(
          (a, b) =>
            a.position - b.position || (a.puzzleId < b.puzzleId ? -1 : a.puzzleId > b.puzzleId ? 1 : 0),
        )
        .map((m) => m.puzzleId),
    }));

  const progress: Record<string, Progress> = {};
  for (const row of Object.values(rows.progress)) progress[row.puzzleId] = progressFromRow(row);

  const sessions: Record<string, SessionState> = {};
  for (const row of Object.values(rows.sessions)) sessions[row.key] = row.session;

  const state: AppState = { version: 1, puzzles, collections, progress, sessions };
  const resetAt = rows.library_settings[SETTINGS_KEY]?.progressResetAt;
  if (resetAt !== null && resetAt !== undefined) state.progressResetAt = resetAt;
  return state;
}

// ---------------------------------------------------------------------------
// Conflict rules
// ---------------------------------------------------------------------------

/**
 * Counters take the max rather than the sum: both copies count up from the
 * same shared value, so summing would count every attempt both knew about
 * twice. Status follows the most recent attempt. Mirrored by
 * motif_merge_progress on the server, which settles the same conflict when two
 * pushes race.
 */
export function mergeProgressRows(a: ProgressRow, b: ProgressRow): ProgressRow {
  const newer = (b.lastAttemptAt ?? 0) >= (a.lastAttemptAt ?? 0) ? b : a;
  const solved = [a.firstSolvedAt, b.firstSolvedAt].filter((at): at is number => at !== null);
  const last = Math.max(a.lastAttemptAt ?? 0, b.lastAttemptAt ?? 0);
  return {
    puzzleId: a.puzzleId,
    status: newer.status,
    attempts: Math.max(a.attempts, b.attempts),
    mistakes: Math.max(a.mistakes, b.mistakes),
    lastAttemptAt: last || null,
    firstSolvedAt: solved.length ? Math.min(...solved) : null,
  };
}

/** Takes each field from whichever side changed it since the base. */
function threeWay<R extends object>(base: R | undefined, local: R, remote: R, fields: (keyof R)[]): R {
  const out = { ...remote };
  for (const field of fields) {
    if (base) {
      if (!sameRow(local[field], base[field])) out[field] = local[field];
    } else if (remote[field] === null || (Array.isArray(remote[field]) && !(remote[field] as unknown[]).length)) {
      // Never agreed before: the server's copy wins, but not by erasing a
      // value only this device has.
      out[field] = local[field];
    }
  }
  return out;
}

interface Rule<R> {
  /** Both sides have the row and both may have changed it. */
  merge(base: R | undefined, local: R, remote: R): R;
  /** Whether a row this device still has outlives the server's deletion of it. */
  outlivesRemoteDelete(local: R, deletedAt: number): boolean;
  /**
   * Whether a row the server changed comes back after this device deleted it.
   *
   * Only for progress, and only because the deletion is re-derived anyway: a
   * progress row goes when its puzzle goes or when progress is reset, and
   * `normalize` applies both of those again. Taking the server's row first is
   * what lets an attempt made elsewhere *after* a reset survive it.
   */
  returnsAfterLocalDelete: boolean;
}

const RULES: { [T in TableName]: Rule<RowOf<T>> } = {
  library_settings: {
    merge: (_base, local, remote) => ({
      progressResetAt:
        Math.max(local.progressResetAt ?? 0, remote.progressResetAt ?? 0) || null,
    }),
    outlivesRemoteDelete: () => true,
    returnsAfterLocalDelete: true,
  },
  puzzles: {
    // Position and solutions never change for an id; only metadata does.
    merge: (base, local, remote) =>
      threeWay(base, local, remote, ['tags', 'comment', 'sourceId', 'rating']),
    outlivesRemoteDelete: () => false,
    returnsAfterLocalDelete: false,
  },
  collections: {
    merge: (base, local, remote) => threeWay(base, local, remote, ['name']),
    outlivesRemoteDelete: () => false,
    returnsAfterLocalDelete: false,
  },
  collection_puzzles: {
    merge: (_base, _local, remote) => remote,
    outlivesRemoteDelete: () => false,
    returnsAfterLocalDelete: false,
  },
  progress: {
    merge: (_base, local, remote) => mergeProgressRows(local, remote),
    outlivesRemoteDelete: (local, deletedAt) => (local.lastAttemptAt ?? 0) > deletedAt,
    returnsAfterLocalDelete: true,
  },
  sessions: {
    // A queue and its cursor only mean something together, so the more
    // recently played session wins outright.
    merge: (_base, local, remote) => (local.lastActiveAt > remote.lastActiveAt ? local : remote),
    outlivesRemoteDelete: (local, deletedAt) => local.lastActiveAt > deletedAt,
    returnsAfterLocalDelete: false,
  },
};

function cloneRows(rows: RowSet): RowSet {
  const out = emptyRows();
  for (const table of TABLES) (out[table] as Record<string, unknown>) = { ...rows[table] };
  return out;
}

/**
 * Folds the server's changed rows into this device's rows.
 *
 * Returns the merged rows and the new base. A row unchanged here since the
 * base simply takes the server's version; a row changed on both sides goes
 * through its table's rule. A deletion on either side wins over an edit on
 * the other, except where the rule says otherwise.
 */
export function integrate(
  local: RowSet,
  base: RowSet,
  incoming: Partial<RemoteRows>,
): { rows: RowSet; base: RowSet } {
  const rows = cloneRows(local);
  const nextBase = cloneRows(base);

  for (const table of TABLES) {
    const rule = RULES[table] as Rule<RowOf<typeof table>>;
    const target = rows[table] as Record<string, RowOf<typeof table>>;
    const targetBase = nextBase[table] as Record<string, RowOf<typeof table>>;

    for (const remote of incoming[table] ?? []) {
      const { key } = remote;
      const before = base[table][key] as RowOf<typeof table> | undefined;
      const mine = local[table][key] as RowOf<typeof table> | undefined;

      if (remote.deletedAt !== null) {
        delete targetBase[key];
        if (!(mine && rule.outlivesRemoteDelete(mine, remote.deletedAt))) delete target[key];
        continue;
      }

      targetBase[key] = remote.row;
      if (!mine) {
        if (!before || rule.returnsAfterLocalDelete) target[key] = remote.row;
      } else if (before && sameRow(mine, before)) {
        target[key] = remote.row;
      } else {
        target[key] = rule.merge(before, mine, remote.row);
      }
    }
  }

  return { rows, base: nextBase };
}

/**
 * Adopts the server's answer to a push.
 *
 * The server may have merged what was sent — kept a deletion, taken a higher
 * attempt count — so the row it returns is the truth for both this device's
 * copy and the base.
 */
export function applyReturned(
  local: RowSet,
  base: RowSet,
  returned: Partial<RemoteRows>,
): { rows: RowSet; base: RowSet } {
  const rows = cloneRows(local);
  const nextBase = cloneRows(base);
  for (const table of TABLES) {
    for (const remote of returned[table] ?? []) {
      const target = rows[table] as Record<string, unknown>;
      const targetBase = nextBase[table] as Record<string, unknown>;
      if (remote.deletedAt !== null) {
        delete target[remote.key];
        delete targetBase[remote.key];
      } else {
        target[remote.key] = remote.row;
        targetBase[remote.key] = remote.row;
      }
    }
  }
  return { rows, base: nextBase };
}

/** What has to be pushed for the server to match these rows. */
export function diff(rows: RowSet, base: RowSet, now: number): Changes {
  const changes = Object.fromEntries(TABLES.map((table) => [table, []])) as unknown as Changes;
  for (const table of TABLES) {
    const out = changes[table] as OutgoingRow[];
    for (const [key, row] of Object.entries(rows[table])) {
      if (!sameRow(row, base[table][key])) out.push({ row, deletedAt: null });
    }
    // Settings are never deleted: there is always exactly one row.
    if (table === 'library_settings') continue;
    for (const [key, row] of Object.entries(base[table])) {
      if (!(key in rows[table])) out.push({ row, deletedAt: now });
    }
  }
  return changes;
}

export function hasChanges(changes: Changes): boolean {
  return TABLES.some((table) => changes[table].length > 0);
}

// ---------------------------------------------------------------------------
// Keeping the rows coherent
// ---------------------------------------------------------------------------

function newerMetadata(winner: PuzzleRow, loser: PuzzleRow): PuzzleRow {
  // A re-import is how an edited comment arrives, so metadata comes from the
  // more recently added copy, falling back to the other for anything it lacks.
  const newer = loser.addedAt > winner.addedAt ? loser : winner;
  const older = newer === winner ? loser : winner;
  return {
    ...winner,
    tags: newer.tags.length ? newer.tags : older.tags,
    comment: newer.comment ?? older.comment,
    rating: newer.rating ?? older.rating,
    sourceId: newer.sourceId ?? older.sourceId,
  };
}

/** Earlier wins, id breaks ties: every device picks the same one. */
function earlier<R extends { id: string }>(a: R, b: R, at: (row: R) => number): R {
  if (at(a) !== at(b)) return at(a) < at(b) ? a : b;
  return a.id < b.id ? a : b;
}

function remapSession(session: SessionState, remap: (id: string) => string): SessionState {
  return {
    ...session,
    queue: session.queue.map(remap),
    current: session.current === null ? null : remap(session.current),
    retries: session.retries.map((retry) => ({ ...retry, puzzleId: remap(retry.puzzleId) })),
    solvedIds: session.solvedIds.map(remap),
    failedIds: session.failedIds.map(remap),
  };
}

/**
 * Restores the invariants the app relies on after rows arrive from elsewhere.
 *
 * - One puzzle per content key. Two devices importing the same file create two
 *   ids for one puzzle; the one the server already has wins, and everything
 *   pointing at the other is moved over.
 * - One collection per name, for the same reason.
 * - Nothing older than a progress reset.
 * - No reference to a puzzle or collection that no longer exists.
 */
export function normalize(input: RowSet, base: RowSet): RowSet {
  const rows = cloneRows(input);
  const known = (table: 'puzzles' | 'collections', id: string) => id in base[table];

  // --- Reset ---
  const resetAt = rows.library_settings[SETTINGS_KEY]?.progressResetAt ?? null;
  if (resetAt !== null) {
    for (const [key, row] of Object.entries(rows.progress)) {
      if ((row.lastAttemptAt ?? 0) < resetAt) delete rows.progress[key];
    }
    for (const [key, row] of Object.entries(rows.sessions)) {
      if (row.lastActiveAt < resetAt) delete rows.sessions[key];
    }
  }

  // --- Duplicate puzzles ---
  const puzzleMap = new Map<string, string>();
  const byContent = new Map<string, PuzzleRow>();
  for (const row of Object.values(rows.puzzles)) {
    const held = byContent.get(row.contentKey);
    if (!held) {
      byContent.set(row.contentKey, row);
      continue;
    }
    const heldKnown = known('puzzles', held.id);
    const rowKnown = known('puzzles', row.id);
    const winner =
      heldKnown !== rowKnown ? (heldKnown ? held : row) : earlier(held, row, (r) => r.addedAt);
    const loser = winner === held ? row : held;
    byContent.set(row.contentKey, newerMetadata(winner, loser));
    puzzleMap.set(loser.id, winner.id);
  }
  if (puzzleMap.size) {
    // A chain cannot form — each loser is dropped the moment it loses — but
    // resolving through the map costs nothing and would survive one.
    const remap = (id: string) => {
      let at = id;
      while (puzzleMap.has(at)) at = puzzleMap.get(at)!;
      return at;
    };
    rows.puzzles = {};
    for (const row of byContent.values()) rows.puzzles[row.id] = row;

    const memberships: Record<string, MembershipRow> = {};
    for (const m of Object.values(rows.collection_puzzles)) {
      const moved = { ...m, puzzleId: remap(m.puzzleId) };
      const key = membershipKey(moved.collectionId, moved.puzzleId);
      const held = memberships[key];
      if (!held || moved.position < held.position) memberships[key] = moved;
    }
    rows.collection_puzzles = memberships;

    const progress: Record<string, ProgressRow> = {};
    for (const row of Object.values(rows.progress)) {
      const moved = { ...row, puzzleId: remap(row.puzzleId) };
      const held = progress[moved.puzzleId];
      progress[moved.puzzleId] = held ? mergeProgressRows(held, moved) : moved;
    }
    rows.progress = progress;

    for (const [key, row] of Object.entries(rows.sessions)) {
      rows.sessions[key] = { ...row, session: remapSession(row.session, remap) };
    }
  }

  // --- Duplicate collections ---
  const byName = new Map<string, CollectionRow>();
  const collectionMap = new Map<string, string>();
  for (const row of Object.values(rows.collections)) {
    const held = byName.get(row.name);
    if (!held) {
      byName.set(row.name, row);
      continue;
    }
    const heldKnown = known('collections', held.id);
    const rowKnown = known('collections', row.id);
    const winner =
      heldKnown !== rowKnown ? (heldKnown ? held : row) : earlier(held, row, (r) => r.createdAt);
    const loser = winner === held ? row : held;
    byName.set(row.name, { ...winner, createdAt: Math.min(winner.createdAt, loser.createdAt) });
    collectionMap.set(loser.id, winner.id);
  }
  if (collectionMap.size) {
    rows.collections = {};
    for (const row of byName.values()) rows.collections[row.id] = row;

    // The loser's puzzles are appended to the winner in their own order, after
    // everything the winner already holds.
    const highest = new Map<string, number>();
    for (const m of Object.values(rows.collection_puzzles)) {
      if (collectionMap.has(m.collectionId)) continue;
      highest.set(m.collectionId, Math.max(highest.get(m.collectionId) ?? 0, m.position));
    }
    const memberships: Record<string, MembershipRow> = {};
    const moving: MembershipRow[] = [];
    for (const [key, m] of Object.entries(rows.collection_puzzles)) {
      if (collectionMap.has(m.collectionId)) moving.push(m);
      else memberships[key] = m;
    }
    moving.sort((a, b) => a.position - b.position || (a.puzzleId < b.puzzleId ? -1 : 1));
    for (const m of moving) {
      const collectionId = collectionMap.get(m.collectionId)!;
      const key = membershipKey(collectionId, m.puzzleId);
      if (memberships[key]) continue;
      const position = (highest.get(collectionId) ?? 0) + 1;
      highest.set(collectionId, position);
      memberships[key] = { collectionId, puzzleId: m.puzzleId, position };
    }
    rows.collection_puzzles = memberships;

    const sessions: Record<string, SessionRow> = {};
    for (const row of Object.values(rows.sessions)) {
      const key = collectionMap.get(row.key) ?? row.key;
      const collectionId = row.session.collectionId;
      const moved: SessionRow = {
        key,
        lastActiveAt: row.lastActiveAt,
        session:
          collectionId && collectionMap.has(collectionId)
            ? { ...row.session, collectionId: collectionMap.get(collectionId)! }
            : row.session,
      };
      const held = sessions[key];
      if (!held || moved.lastActiveAt > held.lastActiveAt) sessions[key] = moved;
    }
    rows.sessions = sessions;
  }

  // --- Dangling references ---
  for (const [key, m] of Object.entries(rows.collection_puzzles)) {
    if (!rows.puzzles[m.puzzleId] || !rows.collections[m.collectionId]) {
      delete rows.collection_puzzles[key];
    }
  }
  for (const key of Object.keys(rows.progress)) {
    if (!rows.puzzles[key]) delete rows.progress[key];
  }
  const alive = new Set(Object.keys(rows.puzzles));
  for (const [key, row] of Object.entries(rows.sessions)) {
    const { collectionId } = row.session;
    if (collectionId && !rows.collections[collectionId]) {
      delete rows.sessions[key];
      continue;
    }
    const session = reconcile(row.session, alive);
    // A session with nothing left to serve is over; keeping it would show a
    // "Resume" button that opens an empty screen.
    if (!session.queue.length) delete rows.sessions[key];
    else if (session !== row.session) rows.sessions[key] = { ...row, session };
  }

  return rows;
}

/**
 * Replays changes made while a sync was in flight onto its result.
 *
 * A sync reads the library, talks to the server for a while, and returns a
 * merged library. Anything recorded in between — a solve, a comment — is in
 * `current` but not in `merged`, and adopting `merged` as-is would drop it.
 * Every row that differs between `used` (what the sync started from) and
 * `current` is an edit made in that window, so it is laid over the result.
 * The next sync pushes it.
 */
export function rebase(used: AppState, current: AppState, merged: AppState): AppState {
  if (current === used) return merged;
  const base = merged.sync?.base ?? emptyRows();
  const before = toRows(used, base);
  const after = toRows(current, base);
  const rows = toRows(merged, base);

  for (const table of TABLES) {
    const target = rows[table] as Record<string, unknown>;
    const keys = new Set([...Object.keys(before[table]), ...Object.keys(after[table])]);
    for (const key of keys) {
      const was = before[table][key];
      const now = after[table][key];
      if (sameRow(was, now)) continue;
      if (now === undefined) delete target[key];
      else target[key] = now;
    }
  }

  const state = fromRows(normalize(rows, base));
  if (merged.sync) state.sync = merged.sync;
  return state;
}
