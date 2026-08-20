import { parseUci } from '../move';
import type { Uci } from '../move';
import { contentKey } from '../puzzle';
import type { Puzzle } from '../puzzle';

/**
 * The JSON import format.
 *
 * ```json
 * { "collection": "Back-rank mates",
 *   "puzzles": [
 *     { "fen": "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1",
 *       "solutions": [["a1a8"]],
 *       "tags": ["backRank"],
 *       "comment": "No luft.",
 *       "rating": 900 }
 *   ] }
 * ```
 */
export interface ImportResult {
  /** Puzzles new to the library. */
  inserted: Puzzle[];
  /**
   * Puzzles already present by content key. Metadata should be refreshed from
   * these, but no new row created.
   */
  updated: Puzzle[];
  /** Rejected entries with reasons, so the import screen can show them. */
  rejected: { index: number; reason: string }[];
  collectionName?: string;
}

function emptyResult(): ImportResult {
  return { inserted: [], updated: [], rejected: [] };
}

/**
 * A cheap structural check, not a legality check. The model has no board; a
 * position that parses here but is illegal is caught by chess.js when the UI
 * first renders it, which is early enough.
 */
export function isPlausibleFen(fen: string): boolean {
  const fields = fen.trim().split(/\s+/);
  if (fields.length < 2) return false;
  if (fields[1] !== 'w' && fields[1] !== 'b') return false;

  const ranks = fields[0].split('/');
  if (ranks.length !== 8) return false;

  for (const rank of ranks) {
    let count = 0;
    for (const ch of rank) {
      if (ch >= '1' && ch <= '8') count += Number(ch);
      else if ('prnbqkPRNBQK'.includes(ch)) count += 1;
      else return false;
    }
    if (count !== 8) return false;
  }

  // Exactly one king per side, or the position cannot be played.
  const kings = (side: string) => [...fields[0]].filter((c) => c === side).length;
  return kings('K') === 1 && kings('k') === 1;
}

/** Parses a line of UCI moves, returning null if any move is malformed. */
function parseLine(raw: unknown): Uci[] | null {
  if (!Array.isArray(raw)) return null;
  const out: Uci[] = [];
  for (const item of raw) {
    if (typeof item !== 'string') return null;
    const move = parseUci(item);
    if (!move) return null;
    out.push(move);
  }
  return out;
}

interface RawEntry {
  fen?: unknown;
  setupMove?: unknown;
  solutions?: unknown;
  tags?: unknown;
  comment?: unknown;
  sourceId?: unknown;
  rating?: unknown;
}

/**
 * Parses and validates a JSON import payload.
 *
 * `existingKeys` are the content keys already in the library; entries matching
 * one are routed to `updated` rather than `inserted`. Duplicates *within* the
 * same file are collapsed the same way, so a file listing a puzzle twice
 * yields one row.
 */
export function importJson(text: string, existingKeys = new Set<string>()): ImportResult {
  const result = emptyResult();

  let parsed: { collection?: unknown; puzzles?: unknown };
  try {
    parsed = JSON.parse(text);
  } catch (error) {
    result.rejected.push({ index: -1, reason: `Not valid JSON: ${(error as Error).message}` });
    return result;
  }

  if (typeof parsed.collection === 'string') result.collectionName = parsed.collection;
  if (!Array.isArray(parsed.puzzles)) {
    result.rejected.push({ index: -1, reason: 'Missing a "puzzles" array' });
    return result;
  }

  const seen = new Set(existingKeys);

  parsed.puzzles.forEach((raw: RawEntry, index: number) => {
    if (typeof raw?.fen !== 'string' || !isPlausibleFen(raw.fen)) {
      result.rejected.push({ index, reason: 'Malformed FEN' });
      return;
    }

    if (!Array.isArray(raw.solutions) || raw.solutions.length === 0) {
      result.rejected.push({ index, reason: 'Puzzle has no solution' });
      return;
    }

    const solutions: Uci[][] = [];
    for (const rawLine of raw.solutions) {
      const line = parseLine(rawLine);
      if (!line || line.length === 0) {
        result.rejected.push({ index, reason: 'Solution contains a malformed move' });
        return;
      }
      // A line must end on the solver's move; a trailing opponent reply would
      // mean the puzzle ends without the solver doing anything.
      if (line.length % 2 !== 1) {
        result.rejected.push({ index, reason: 'Solution line ends on an opponent move' });
        return;
      }
      solutions.push(line);
    }

    let setupMove: Uci | undefined;
    if (raw.setupMove !== undefined) {
      const parsedSetup = typeof raw.setupMove === 'string' ? parseUci(raw.setupMove) : null;
      if (!parsedSetup) {
        result.rejected.push({ index, reason: 'Malformed setup move' });
        return;
      }
      setupMove = parsedSetup;
    }

    const puzzle: Puzzle = {
      id: crypto.randomUUID(),
      fen: raw.fen,
      setupMove,
      solutions,
      tags: Array.isArray(raw.tags) ? raw.tags.filter((t): t is string => typeof t === 'string') : [],
      comment: typeof raw.comment === 'string' ? raw.comment : undefined,
      sourceId: typeof raw.sourceId === 'string' ? raw.sourceId : undefined,
      rating: typeof raw.rating === 'number' ? raw.rating : undefined,
      addedAt: Date.now(),
    };

    const key = contentKey(puzzle);
    if (seen.has(key)) {
      result.updated.push(puzzle);
    } else {
      seen.add(key);
      result.inserted.push(puzzle);
    }
  });

  return result;
}
