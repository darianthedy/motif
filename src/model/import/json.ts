import { firstIllegalMove, isValidFen, pieceAt, withPiece } from '../board';
import { parseUci } from '../move';
import type { Uci } from '../move';
import { contentKey, parsePlacement, placementText } from '../puzzle';
import type { Placement, PuzzleContent } from '../puzzle';

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
 *
 * A missing-piece puzzle carries `add_piece` and no solutions. The piece is
 * written FEN-style, so its case is its colour — `Ng6` is a white knight:
 *
 * ```json
 * { "fen": "6rk/6pp/8/1p1b4/p7/3P4/PPP5/1K5R b - - 0 1",
 *   "solutions": [],
 *   "tags": ["missingPiece"],
 *   "comment": "Add a knight and it's mate",
 *   "add_piece": "Ng6" }
 * ```
 */
/**
 * One collection's worth of puzzles from an import file.
 *
 * A file may carry several — the 1001-exercises book is 18 chapters, and
 * splitting it by hand would be absurd. A single-collection file is simply a
 * file with one group, so there is one code path rather than two.
 */
export interface ImportGroup {
  name?: string;
  /** In file order, each puzzle once. */
  puzzles: PuzzleContent[];
}

export interface ImportResult {
  groups: ImportGroup[];
  /** Rejected entries with reasons, so the import screen can show them. */
  rejected: { index: number; reason: string }[];
  /** Convenience for the common single-collection file. */
  collectionName?: string;
}

function emptyResult(): ImportResult {
  return { groups: [], rejected: [] };
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
  id?: unknown;
  fen?: unknown;
  solutions?: unknown;
  tags?: unknown;
  comment?: unknown;
  rating?: unknown;
  add_piece?: unknown;
}

/**
 * Parses and validates a JSON import payload.
 *
 * Accepts either a single collection object or an array of them, so a whole
 * multi-chapter book imports in one go. A puzzle listed twice in one group
 * appears once, where it was first listed, with the later entry's details.
 *
 * Rejection indices are file-wide rather than per group, so a reported row
 * number means something to someone scrolling the file.
 */
export function importJson(text: string): ImportResult {
  const result = emptyResult();

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (error) {
    result.rejected.push({ index: -1, reason: `Not valid JSON: ${(error as Error).message}` });
    return result;
  }

  const blocks = Array.isArray(parsed) ? parsed : [parsed];
  let index = 0;

  for (const block of blocks) {
    const group = block as { collection?: unknown; puzzles?: unknown };
    if (!Array.isArray(group?.puzzles)) {
      result.rejected.push({ index, reason: 'Missing a "puzzles" array' });
      continue;
    }

    const name = typeof group.collection === 'string' ? group.collection : undefined;
    const puzzles = new Map<string, PuzzleContent>();

    for (const raw of group.puzzles as RawEntry[]) {
      const puzzle = parseEntry(raw, index++, result);
      if (puzzle) puzzles.set(contentKey(puzzle), puzzle);
    }

    result.groups.push({ name, puzzles: [...puzzles.values()] });
  }

  if (result.groups.length === 1) result.collectionName = result.groups[0].name;
  return result;
}

/** Validates one entry, recording a reason on the result if it is rejected. */
function parseEntry(raw: RawEntry, index: number, result: ImportResult): PuzzleContent | null {
  if (typeof raw?.fen !== 'string' || !isValidFen(raw.fen)) {
    result.rejected.push({ index, reason: 'Malformed FEN' });
    return null;
  }

  // The two kinds are told apart by the data rather than by a declared type,
  // and the same file may hold both.
  const rawPlacement = raw.add_piece;
  if (rawPlacement !== undefined && rawPlacement !== null) {
    if (Array.isArray(raw.solutions) && raw.solutions.length > 0) {
      result.rejected.push({
        index,
        reason: 'A missing-piece puzzle answers with a piece, so it can carry no solution',
      });
      return null;
    }
    const addPiece = parseAddPiece(rawPlacement, raw.fen, index, result);
    if (!addPiece) return null;
    return { ...common(raw), fen: raw.fen, solutions: [], addPiece };
  }

  if (!Array.isArray(raw.solutions) || raw.solutions.length === 0) {
    result.rejected.push({ index, reason: 'Puzzle has no solution' });
    return null;
  }

  const solutions: Uci[][] = [];
  for (const rawLine of raw.solutions) {
    const line = parseLine(rawLine);
    if (!line || line.length === 0) {
      result.rejected.push({ index, reason: 'Solution contains a malformed move' });
      return null;
    }
    // Either parity is a real line. Odd length ends on the solver's move; even
    // length ends on the opponent's forced reply, which is how you author "and
    // now he must take, and that's the point" — the last move is played for you
    // and the puzzle stops there.
    solutions.push(line);
  }

  // Legality is checked once, here, rather than discovered when someone is
  // three wrong tries deep into a puzzle that cannot be solved.
  const illegal = firstIllegalMove(raw.fen, solutions);
  if (illegal) {
    result.rejected.push({
      index,
      reason: `Move ${illegal.move} is illegal at ply ${illegal.ply + 1}`,
    });
    return null;
  }

  return { ...common(raw), fen: raw.fen, solutions };
}

/** The fields both kinds share, so neither can drift from the other. */
function common(raw: RawEntry) {
  return {
    tags: Array.isArray(raw.tags) ? raw.tags.filter((t): t is string => typeof t === 'string') : [],
    comment: typeof raw.comment === 'string' ? raw.comment : undefined,
    // The book numbers its puzzles; keeping that as the source id makes a
    // puzzle findable in the original.
    sourceId:
      typeof raw.id === 'number' || typeof raw.id === 'string' ? String(raw.id) : undefined,
    rating: typeof raw.rating === 'number' ? raw.rating : undefined,
  };
}

/**
 * Validates the piece a missing-piece puzzle asks for.
 *
 * Everything here is checked at import for the same reason the move legality is:
 * a placement that cannot be made is a puzzle with no right answer, and the only
 * good time to find that out is before it is in the library.
 */
function parseAddPiece(
  rawPlacement: unknown,
  start: string,
  index: number,
  result: ImportResult,
): Placement | null {
  const placement = typeof rawPlacement === 'string' ? parsePlacement(rawPlacement) : null;
  if (!placement) {
    result.rejected.push({
      index,
      reason: 'Malformed piece to add — write it FEN-style, like "Ng6" or "ng6"',
    });
    return null;
  }

  if (placement.type === 'k') {
    result.rejected.push({ index, reason: 'A king cannot be added — there is already one' });
    return null;
  }

  if (pieceAt(start, placement.square)) {
    result.rejected.push({
      index,
      reason: `Square ${placement.square} is not empty, so nothing can be added to it`,
    });
    return null;
  }

  if (!withPiece(start, placement)) {
    result.rejected.push({
      index,
      reason: `${placementText(placement)} does not make a legal position`,
    });
    return null;
  }

  return placement;
}
